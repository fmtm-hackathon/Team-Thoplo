-- The Area of Interest boundary provided by the person creating the project
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
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
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'trunk'
    OR tags->>'highway' = 'primary'
    OR tags->>'highway' = 'secondary'
    OR tags->>'highway' = 'tertiary'
    OR tags->>'highway' = 'residential'
    OR tags->>'highway' = 'unclassified'
    OR tags->>'waterway' = 'river'
    OR tags->>'waterway' = 'drain'
    OR tags->>'railway' IS NOT NULL
    )
)
-- Merge all lines, necessary so that the polygonize function works later
,merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
)
-- Combine the boundary of the AOI with the splitlines
-- TODO: Is it better to do this before merging?
,comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
)
-- Polygonize; create a polygon for each area enclosed by the splitlines
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
-- Add the count of features in the splitpolygon each building belongs to
-- to the buildings table; sets us up to be able to run the clustering
,buildingstocluster AS (
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
-- TODO: this should certainly not be a hardcoded, the number of features
-- per cluster should come from a project configuration table
,clusteredbuildings AS (
SELECT 
  *,
  ST_ClusterKMeans(geom, cast((b.numfeatures / 10) + 1 as integer)) 
  over (partition by polyid) as cid
FROM buildingstocluster b
)

select * from clusteredbuildings

