import json, math, sugar, sequtils, strformat

type
  GeoType* = enum
    gtPoint = "Point",
    gtMultiPoint = "MultiPoint",
    gtLineString = "LineString",
    gtMultiLineString = "MultiLineString",
    gtPolygon = "Polygon",
    gtMultiPolygon = "MultiPolygon",

  #TODO Include elevation?
  Position* = array[2, float64]

  Point* = Position
  MultiPoint* = seq[Point]
  LineString* = seq[Point]
  MultiLineString* = seq[LineString]
  Polygon* = seq[LineString]
  MultiPolygon* = seq[Polygon]

  GeoObject*[T, RetType] = ref object
    `type`*: string
    coordinates*: T
    bbox*: JsonNode

  GeometryCollection* = ref object
    geometries*: JsonNode

  Feature* = ref object
    id: int
    `type`*: string
    geometry*: JSONNode
    properties*: JsonNode
    bbox*: JsonNode

  FeatureCollection* = ref object
    features*: JsonNode
    bbox*: JsonNode

proc `$`*(g: GeoObject): string =
  fmt"{g.type} - {g.coordinates}"

proc `%`(g: GeoObject): JsonNode =
  result = newJObject()
  result["type"] = %g.type
  result["coordinates"] = %g.coordinates

proc `[]`*(g: GeoObject, x: int): GeoObject.RetType =
  g.coordinates[x]

func newPoint*(x, y: float64, bbox: JsonNode = newJNull()): GeoObject[Point, float64] =
  GeoObject[Point, float64](type: $gtPoint, coordinates: [x, y])

func newMultiPoint*(points: seq[Point], bbox: JsonNode = newJNull()): GeoObject[MultiPoint, Point] =
  GeoObject[MultiPoint, Point](type: $gtMultiPoint, coordinates: points)

func newLineString*(points: seq[Point], bbox: JsonNode = newJNull()): GeoObject[LineString, Point] =
  assert points.len >= 2, "LineString objects must have at least 2 Points"
  GeoObject[LineString, Point](type: $gtLineString, coordinates: points)

func newMultiLineString*(lines: seq[LineString], bbox: JsonNode = newJNull()): GeoObject[MultiLineString, LineString] =
  assert all(lines, l => l.len >= 2), "Each LineString object must have at least 2 Points"
  GeoObject[MultiLineString, LineString](type: $gtMultiLineString, coordinates: lines)

func newPolygon*(lines: seq[LineString], bbox: JsonNode = newJNull()): GeoObject[Polygon, LineString] =
  # Rings must have identical starting and ending coordinates
  assert all(lines, il => il[0] == il[^1]), "Each linear ring must end where it started"
  assert all(lines, l => l.len >= 4), "Each linear ring must contain at least 4 Positions"
  GeoObject[Polygon, LineString](type: $gtPolygon, coordinates: lines)

func newGeometryCollection*(geometries: seq[GeoObject], bbox: JsonNode = newJNull()): GeometryCollection =
  let payload = newJArray()
  for gl in geometries.items:
    payload.add(%gl)
  GeometryCollection(geometries: payload)

func newFeature*(id: int = -1, geometry, properties, bbox: JsonNode = newJNull()): Feature =
  Feature(id: id, type: "Feature", geometry: geometry, properties: properties, bbox: bbox)

func newFeature*(id: int = -1, geometry: GeoObject, properties, bbox: JsonNode = newJNull()): Feature =
  newFeature(id = id, geometry = %geometry, properties = properties, bbox = bbox)

func newFeatureCollection*(features: seq[Feature], bbox: JsonNode = newJNull()): FeatureCollection =
  FeatureCollection(features: %features, bbox: bbox)

func newFeatureCollection*(features: JsonNode = newJArray(), bbox: JsonNode = newJNull()): FeatureCollection =
  FeatureCollection(features: features, bbox: bbox)

proc fromJson*(data: JsonNode): FeatureCollection =
  assert data.kind == JObject
  assert $data{"type"} == "FeatureCollection"

  var features = newSeq[Feature]()
  for featureData in data["features"].items:
    let
      geometry = featureData{"geometry"}
      properties = featureData{"properties"}
      id = featureData{"id"}.getInt

    features.add(newFeature(id = id, geometry = geometry, properties = properties))
  result = newFeatureCollection(features)

when isMainModule:
  import unittest

  suite "GeoJson Tests":

    test "Base type testing":
      let p = GeoObject[Point, float64](coordinates: [1.0, 2.0])
      check p.coordinates[0] == 1.float64
      check p.coordinates[1] == 2.float64

      let mp = GeoObject[MultiPoint, Point](coordinates: @[[1.0, 2.0], [3.0, 4.0]])
      check mp.coordinates[0][0] == 1.0
      check mp.coordinates[1][1] == 4.0

      let ls = GeoObject[LineString, Point](coordinates: @[[1.0, 2.0], [3.0, 4.0]])
      check mp.coordinates[0][0] == 1.0
      check mp.coordinates[1][1] == 4.0

    test "Point Tests":
      let point = newPoint(0.1, 0.2)
      check point[0] == 0.1
      check point[1] == 0.2

      let multipoint = newMultiPoint(
        @[
          [0.1, 0.2],
          [0.3, 0.4]
        ]
      )
      check multipoint.coordinates[0][1] == 0.2
      check multipoint.coordinates[1][0] == 0.3

    test "Line Tests":
      let linestring = newLineString(
        @[
          [0.1, 0.2],
          [0.3, 0.4]
        ]
      )
      check linestring.coordinates[0][0] == 0.1
      check linestring.coordinates[1][1] == 0.4

      expect AssertionError:
        let badlinestring = newLineString(
          @[
            [0.1, 0.2]
          ]
        )

      expect AssertionError:
        let badmlinestring = newMultiLineString(
          @[
            @[
              [0.1, 0.2]
            ],
            @[
              [0.1, 0.2],
              [1.1, 1.2],
              [2.1, 2.2],
            ],
          ]
        )

      let multilinestring = newMultiLineString(
        @[
          @[
            [0.1, 0.2],
            [10.1, 1.2],
            [20.1, 2.2],
          ],
          @[
            [0.1, 0.2],
            [1.1, 1.2],
            [2.1, 2.2],
          ],
        ]
      )
      check multilinestring[0][2][0] == 20.1
      check multilinestring[1][0][1] == 0.2

    test "Polygon Tests":
      let rings = @[
        # Make a small square
        @[
          [0.0, 0.0],
          [1.0, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.0, 0.0]
        ],
        # And an inside, smaller hole
        @[
          [0.3, 0.3],
          [0.6, 0.3],
          [0.6, 0.6],
          [0.3, 0.6],
          [0.3, 0.3]
        ],
      ]
      let polygon = newPolygon(rings)
      check polygon[0][0][0] == 0.0


      let badrings = @[
        # Make an ill-formed polygon
        @[
          [0.0, 0.0],
          [1.0, 0.0],
          [1.0, 1.0],
          [0.0, 1.0],
          [0.0, 2.0]
        ],
      ]
      expect AssertionError:
        let badpolygon = newPolygon(badrings)

      let smallrings = @[
        # Make an polygon with invalid polygon dimensions (not enough points)
        @[
          [0.0, 0.0],
          [1.0, 0.0],
          [0.0, 0.0],
        ],
      ]
      expect AssertionError:
        let linepolygon = newPolygon(smallrings)

    test "Geometric Collection Tests":
      let geometries: seq[GeoObject[Point, float64]] = toSeq(1 .. 5).map(i => newPoint(i.float * 1.0, i.float * -1.0))

      let gcollection = newGeometryCollection(geometries)
      # Check that values have been correctly converted
      var c = 1.0
      for node in gcollection.geometries.items:
        check node["coordinates"][0].getFloat == c * 1.0
        check node["coordinates"][1].getFloat == c * -1.0
        c += 1.0

    test "Feature Tests":

      # Test empty feature
      let emptyFeature = newFeature()
      check emptyFeature.type == "Feature"
      check emptyFeature.id == -1
      check emptyFeature.geometry.kind == JNull

      let geoFeature = newFeature(id = 22, geometry = newMultiLineString(@[
        @[
          [0.0, 0.1],
          [3.0, 3.1]
        ],
        @[
          [1.1, 2.2],
          [1.14, 7.2],
        ]
      ]))
      check geoFeature.id == 22
      check geoFeature.geometry{"coordinates"}[0][0][1].getFloat == 0.1

      let
        properties = %* {"test": "TestValue"}
        propsFeature = newFeature(properties = properties)
      check propsFeature.properties{"test"}.getStr == "TestValue"

    test "Feature Collection Tests":
      let geoFeatures = @[
        newFeature(geometry = newMultiLineString(@[
          @[
            [0.0, 0.1],
            [3.0, 3.1]
          ],
          @[
            [1.1, 2.2],
            [1.14, 7.2],
          ]
        ])),
        newFeature(geometry = newLineString(@[
          [0.0, 0.1],
          [3.0, 3.1]
        ])),
      ]

      let fc = newFeatureCollection(geoFeatures)
      check fc.features[0]{"geometry"}{"coordinates"}[0][1][1].getFloat == 3.1
