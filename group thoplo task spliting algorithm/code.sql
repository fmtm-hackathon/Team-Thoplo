--*********************************************************lines and river***********************************************************

WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
)  
SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines



--*************************************************union of boundary and river and roads****************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
  WHERE ST_Intersects(a.geom, l.geom)
  AND (tags->>'highway' = 'primary' OR tags->>'waterway' = 'river')
),
merged AS (
  SELECT ST_LineMerge(ST_Union(splitlines.geom)) AS geom
  FROM splitlines
)
  SELECT ST_Union(boundary.geom, merged.geom) AS geom
  FROM boundary, merged

-- *******************************************dividing into polygons according to river and roads*************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
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
)
  SELECT (ST_Dump(ST_Polygonize(comb.geom))).geom AS geom
  FROM comb


-- ************************************************querying building******************************************************

  SELECT *
  FROM islington_polygons
  WHERE tags->>'building' IS NOT NULL


--******************************************selecting buildings of one polygon***************************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
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
  FROM islington_polygons
  WHERE tags->>'building' IS NOT NULL
)
SELECT buildings.geom
FROM buildings
JOIN polygons ON st_contains(polygons.geom, buildings.geom)
WHERE polygons.geom IN (
    SELECT polygons.geom
    FROM polygons
    ORDER BY polygons.geom 
	OFFSET 13 LIMIT 1)




--*************************************************generating centroid of each building***************************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
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
  FROM islington_polygons
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
	OFFSET 13 LIMIT 1
))
SELECT  st_centroid(geom) AS geom
FROM polbuild

--*******************************************************************clustering buildings*********************************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
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
  FROM islington_polygons
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
	OFFSET 13 LIMIT 1
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
--************************************final code****************************************************************************
--Here is a working sample of our algorith. It can be extended to work for any number of polygons in the future.
--***************generating sections for equal distribution of field mapping task******************************
WITH boundary AS (
  SELECT ST_Boundary(geom) AS geom
  FROM islington_aoi
),
splitlines AS (
  SELECT ST_Intersection(a.geom, l.geom) AS geom
  FROM islington_aoi a, islington_lines l
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
  FROM islington_polygons
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
	OFFSET 12 LIMIT 1
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






