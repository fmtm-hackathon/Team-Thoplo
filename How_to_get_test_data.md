# How to get test data for the FMTM task splitting algorithm

You need a working Postgresql database with a PostGIS extension.

You need three layers (it will be four when I get around to implementing a config table):

1. "project_aoi", a PostGIS layer with a single polygon representing the Area of Interest for the project.
2. "ways_line", a PostGIS layer with all of the lines (usually from OSM) in the AOI that will be used for initial splitting.
3. "ways_poly", a PostGIS layer with all of the poylygons (usually from OSM) including what are the most common feature to be field mapped with the FMTM.

## project_aoi

Easiest way to get this for testing purposes is simply create a Temporary Scratch Layer in QGIS, make it polygon geometry, ensure that the CRS is EPSG:4326, call it ```project_aoi```, draw your AOI, and import it straight into PostGIS using the Database Manager.

Otherwise create a GeoJSON polygon for your AOI using [geojson.io](geojson.io) or whatever, and import it into PostGIS with psql or whatever you wanna use.

## ways_line and ways_poly

These are layers from OSM, imported using the Underpass schema, which deals with the problem of messy attributes by cramming most of them into a ```jsonb``` column in the database. This has the very useful features that a) it doesn't matter how ridiculous the keys and values are, PostGIS isn't trying to use the keys as column headers so it doesn't crash, and b) you can still access whatever tags aren't hot garbage using syntax like ```tags->>'building' IS NOT NULL```.

"How," you ask, "do I get OSM layers using the Underpass schema?"

Excellent question.

### First, get an OSM extract, one of two ways.

1. Go to [Geofabrik's](https://www.geofabrik.de/) awesome, free [download server](http://download.geofabrik.de/index.html), choose a country, and download the entire thing as a .pbf file.
2. Go to the [HOT Export Tool](https://export.hotosm.org/en/v3/exports/new/describe), sign in (or sign up with an OSM account, which you can get for free if you don't have one), and create a new export. On the first tab, Describe, draw an AOI that is slightly bigger than the AOI you're planning to map. Ignore the third tab, Data. On the second tab, Formats, choose ```.pbf```. On the fourth tab, Summary, choose ```Unfiltered files```. Wait until your export is ready and download it.

### Second, extract it with OSM2PGSQL using the Underpass schema
- Install Postgresql and PostGIS, create a database with PostGIS enabled, and make sure you can connect to it.
  - If you don't know how to do that, testing this script is probably not for you anyway.
- Install [OSM2PGSQL](https://osm2pgsql.org/).
- Grab [this config file](https://github.com/hotosm/underpass/blob/master/utils/raw.lua) (in Lua, of all things!). You can either clone the Underpass repo and use ```.../underpass/utils/raw.lua```, or just download the file from the link above.
- Use OSM2PGSQL to shoot the OSM extract into your PostGIS database. Syntax will look a lot like this:
```
osm2pgsql --create -H localhost -U username -P 5432 -d mydatabase -W --extra-attributes --output=flex --style path/to/underpass/utils/raw.lua path/to/myosmextract.osm.pbf 
```

That will, assuming the planets align, fire three layers, ```ways_line```, ```ways_poly```, and ```nodes``` into your PostGIS database. They will all contain a column called ```tags``` with the glorious mess that is OSM attributes in a jsonb column, and the line and polygon layers are most of what you need to work with the script (the only remaining item is the AOI polygon which you must create).

Mileage may vary as there's a *lot* of invalid geometry and otherwise bad data in OSM, and I haven't yet implemented any real error handling. I'd advise starting with a small AOI with no obviously messy data in it. 


