-- The Area of Interest provided by the person creating the project
WITH aoi AS (
  SELECT * FROM "project_aoi"
)
-- Extract all lines to be used as splitlines from a table of lines
-- with the schema from Underpass (all tags as jsonb column called 'tags')
-- TODO: add polygons (closed ways in OSM) with a 'highway' tag;
-- some features such as roundabouts appear as polygons.
-- TODO: add waterway polygons; now a beach doesn't show up as a splitline.
-- TODO: these tags should come from another table rather than hardcoded
-- so that they're easily configured during project creation.
,splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM aoi a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' IS NOT NULL
    OR tags->>'waterway' IS NOT NULL
    OR tags->>'railway' IS NOT NULL
    )
)
-- Merge all lines, necessary so that the polygonize function works later
,merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
)
-- Combine the boundary of the AOI with the splitlines
-- Extract the Area of Interest boundary as a line
,boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM aoi
)
-- And combine it with the splitlines
,comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
)
-- Create a polygon for each area enclosed by the splitlines
,splitpolysnoindex AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom as geom
  FROM comb
)
-- Add an index column to the split polygons
-- Row numbers can function as temporary unique IDs for our new polygons
,splitpolygons AS(
SELECT row_number () over () as polyid, * 
from splitpolysnoindex
)
--
-- Grab the buildings.
-- While we're at it, grab the ID of the polygon the buildings fall within.
-- TODO: at the moment this uses ST_Intersects, which is fine except when
-- buildings cross polygon boundaries (which definitely happens in OSM).
-- In that case, the building should probably be placed in the polygon
-- where the largest proportion of its area falls. At the moment it duplicates
-- the building in 2 polygons, which is bad!
-- There's definitely a way to calculate which of several polygons the largest
-- proportion of a building falls, that's what we should do.
-- Doing it as a left join would also be better.
,buildings AS (
  SELECT b.*, polys.polyid 
  FROM "ways_poly" b, splitpolygons polys
  WHERE ST_Intersects(polys.geom, b.geom)
  AND b.tags->>'building' IS NOT NULL
)
-- Count the features in each task polygon.
,polygonsfeaturecount AS (
  SELECT sp.polyid, sp.geom, count(b.geom) AS numfeatures
  FROM "splitpolygons" sp
  LEFT JOIN "buildings" b
  ON sp.polyid = b.polyid
  GROUP BY sp.polyid, sp.geom
)
-- Filter out polygons with no features in them
,taskpolygons AS (
  SELECT *
  FROM polygonsfeaturecount pfc
  WHERE pfc.numfeatures > 0
)
/* ***********************************
-- Uncomment this and stop here for split polygons before clustering
SELECT * FROM taskpolygons
*************************************/

-- Add the count of features in the splitpolygon each building belongs to
-- to the buildings table; sets us up to be able to run the clustering
,buildingswithcount AS (
  SELECT b.*, p.numfeatures
  FROM buildings b 
  LEFT JOIN polygonsfeaturecount p
  ON b.polyid = p.polyid
)
-- Cluster the buildings within each splitpolygon. The second term in the
-- call to the ST_ClusterKMeans function is the number of clusters to create,
-- so we're dividing the number of features by a constant (10 in this case)
-- to get the number of clusters required to get close to the right number
-- of features per cluster.
-- TODO: This should certainly not be a hardcoded, the number of features
--       per cluster should come from a project configuration table
-- TODO; CRITICAL: Sets of buildings in polygons with less than twice the
--                 number of desired buildings plus one
--                 per task must be excluded from this operation
,buildingstocluster as (
  SELECT * FROM buildingswithcount bc
  WHERE bc.numfeatures > 21
)
,clusteredbuildings AS (
SELECT *,
  ST_ClusterKMeans(geom, cast((b.numfeatures / 10) + 1 as integer)) 
  over (partition by polyid) as cid
FROM buildingstocluster b
)
/* ***********************************
-- Uncomment this and stop here for clustered buildings
SELECT * FROM cluteredbuildings
*************************************/
,hulls AS(
  -- Using a very high param_pctconvex value; smaller values often produce
  -- self-intersections and crash. It seems that anything below 1 produces
  -- something massively better than 1 (which is just a convex hull) but
  -- no different (i.e. 0.99 produces the same thing as 0.9999), so
  -- there's nothing to lose choosing a value a miniscule fraction less than 1.
  select ST_ConcaveHull(ST_Collect(clb.geom), 0.9999) as geom
  from clusteredbuildings clb
  group by clb.cid, clb.polyid
)
-- Now we need to:
--   - Create intersections for the hulls so all overlapping bits are separated
--   - Check what's inside of the overlapping bits
--     - If it's only stuff belonging to one of the original hulls, give that
--       bit to the hull it belongs to
--     - If the overlapping are contains stuff belonging to more than one hull,
--       somehow split the overlapping bit such that each piece only contains
--       stuff from one or another parent hull. Then merge them back.
--  - Do something Voronoi-esque to expand the hulls until they tile the
--    entire AOI, creating task polygons with no gaps
select * from hulls