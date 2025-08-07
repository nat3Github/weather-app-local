### weather data (from open-meteo)

- get data from open meteo
- parse for easier management

### geo location

- via http call
- TODO: native solution for mac / win ?

### generate graphic with cities geo data, country/territory geo data

- city geo data from: https://public.opendatasoft.com/explore/dataset/geonames-all-cities-with-a-population-1000
- DONE: parse json into city attributes struct
- territory geo data from: https://public.opendatasoft.com/explore/dataset/world-administrative-boundaries
- TODO: parse json into boundary struct
- color height map -> interpolate between nearest (city) points?
- render a sector (around a central geo location) with cities

- Q:
- how do we efficiently filter for cities in sector?
- which cities do we pick? -> population size
- cities must not be crowded together! (?group crowded cities together?)

- TODO: Deserialize the City attributes struct (parsing json data on app startup is to slow) and serialize it at startup
- Number of cities is currently ~147k -> we must filter by view-sector lon/lat coordinates -> test iteration speed -> speedup through k-d tree?

### biggest cities in viewport, Naive Algorithm:

prerequisite:

- sort cities array descending
- n = max_num_cities

steps:

- while true iterate cities:
- viewport section coordinates: central coordinate + degree_range
- if lat, lon in bounds of the viewport section coordinates: if (k < n) add city and k+=1 else break

### Problem: City crowded together, Naive Solution:

desc:

- choose bigger number of initial cities
- group nearby cities together -> new list
- choose first k

prerequisites:

- min distance between cities:
- binary array for marked cities

steps:

- for each city
- if marked skip
- mark city
- check with all other cities:
- calc distance, if distance < min distance, remember result
- check the distance of city to other cities

### Problem: Number Cities < Max City Num:

select points where weather data should be gathered
Q: how do we do this?
