--******************lines and river********************************************

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' IS NOT NULL --= 'primary'
    OR tags->>'waterway' = 'river')
    OR tags->>'railway' IS NOT NULL
)  
SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines

--***********union of boundary, river, railways, and roads********************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
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
    OR tags->>'railway' IS NOT NULL)
),
merged AS (
SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
)
SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged

-- ************dividing into polygons by river, roads, and railways***********

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
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
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
splitpolysnoindex AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom as geom
  FROM comb
)
-- Add row numbers to function as temporary unique IDs for our new polygons
SELECT row_number () over () as polyid, * 
from splitpolysnoindex

-- ****************add buildings in the AOI***********************************

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
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
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
splitpolysnoindex AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom as geom
  FROM comb
),
polygons AS(
-- Add row numbers to function as temporary unique IDs for our new polygons
SELECT row_number () over () as polyid, * 
from splitpolysnoindex
),
buildings AS (
  SELECT osmpolys.*
  FROM "project_aoi" aoi, "ways_poly" osmpolys
  WHERE st_intersects(osmpolys.geom, aoi.geom)
  AND osmpolys.tags->>'building' IS NOT NULL
)
SELECT b.*, polys.polyid 
FROM buildings b, polygons polys
WHERE ST_Intersects(polys.geom, b.geom)

--***************selecting buildings of one polygon***************************

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
polygons AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom AS geom
  FROM comb
),
buildings AS (
  SELECT *
  FROM "ways_poly"
  WHERE tags->>'building' IS NOT NULL
)
SELECT buildings.geom
FROM buildings
--this only catches buildings fully within the polygon
--JOIN polygons ON st_contains(polygons.geom, buildings.geom)
--using st_intersects instead catches all even partially within
JOIN polygons ON st_intersects(polygons.geom, buildings.geom)
WHERE polygons.geom IN (
    SELECT polygons.geom
    FROM polygons
    ORDER BY polygons.geom 
	OFFSET 13 LIMIT 1)

--****************generating centroid of each building************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
polygons AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom AS geom
  FROM comb
),
buildings AS (
  SELECT *
  FROM "ways_poly"
  WHERE tags->>'building' IS NOT NULL
),
polbuild AS(
SELECT buildings.geom
FROM buildings
JOIN polygons ON st_contains(polygons.geom, buildings.geom)
WHERE polygons.geom IN (
    SELECT polygons.geom
    FROM polygons
    ORDER BY polygons.geom 
	OFFSET 66 LIMIT 1
))
SELECT  st_centroid(geom) AS geom
FROM polbuild

--**************clustering buildings******************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
polygons AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom AS geom
  FROM comb
),
buildings AS (
  SELECT *
  FROM "ways_poly"
  WHERE tags->>'building' IS NOT NULL
),
polbuild AS(
SELECT buildings.geom
FROM buildings
JOIN polygons ON st_contains(polygons.geom, buildings.geom)
WHERE polygons.geom IN (
    SELECT polygons.geom
    FROM polygons
    ORDER BY polygons.geom 
	OFFSET 66 LIMIT 1
)),
points as(
SELECT  st_centroid(geom) AS geom
FROM polbuild
),
clusters AS (
  SELECT ST_ClusterKMeans(geom, 10) OVER () AS cid, geom
  FROM polbuild
)
select polbuild.geom,cid from polbuild join clusters on st_contains( polbuild.geom, clusters.geom) group by cid, polbuild.geom;
--********************final code***********************************************
--Here is a working sample of our algorithm.
--It can be extended to work for any number of polygons in the future.
--****generating sections for equal distribution of field mapping task*********

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM "project_aoi"
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM "project_aoi" a, "ways_line" l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
),
comb AS (
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged
),
polygons AS (
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom AS geom
  FROM comb
),
buildings AS (
  SELECT *
  FROM "ways_poly"
  WHERE tags->>'building' IS NOT NULL
),
polbuild AS(
SELECT buildings.geom
FROM buildings
JOIN polygons ON st_contains(polygons.geom, buildings.geom)
WHERE polygons.geom IN (
    SELECT polygons.geom
    FROM polygons
    ORDER BY polygons.geom 
	OFFSET 66 LIMIT 1
)),
points as(
SELECT  st_centroid(geom) AS geom
FROM polbuild
),
clusters AS (
  SELECT ST_ClusterKMeans(geom, 15) OVER () AS cid, geom
  FROM polbuild
),
polycluster AS(
select polbuild.geom,cid from polbuild join clusters on st_contains( polbuild.geom, clusters.geom) group by cid, polbuild.geom),

 polyboundary AS (
  SELECT ST_ConvexHull(ST_Collect(polycluster.geom)) AS geom
  FROM polycluster group by cid
)
SELECT polyboundary.geom
FROM polyboundary;






