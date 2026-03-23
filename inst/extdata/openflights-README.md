Bundled OpenFlights sample data

Files:
- `openflights_top20_airports.csv`
- `openflights_top20_routes.csv`

Source:
- https://openflights.org/data.php
- https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
- https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat

Generation:
- keep the 20 airports with the highest outbound route counts in the upstream snapshot
- keep airline route records whose source and destination are both in that 20-airport subset

License and attribution:
- OpenFlights states that the Airport, Airline, Plane and Route Databases are made available under the Open Database License (ODbL) v1.0
- individual contents are licensed under the Database Contents License (DbCL) v1.0
- this bundled subset is included for example and test purposes with source attribution to OpenFlights
