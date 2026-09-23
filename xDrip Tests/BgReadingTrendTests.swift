//
//  BgReadingTrendTests.swift
//  xdripTests
//
//  Created by Paul Plant on 4/9/26.
//  Copyright © 2026 Johan Degraeve. All rights reserved.
//

import CoreData
import XCTest
@testable import xdrip

final class BgReadingTrendTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var coreDataManager: CoreDataManager!

    override func setUp() {
        super.setUp()
        coreDataManager = CoreDataManager(inMemoryModelName: ConstantsCoreData.modelName)
    }

    override func tearDown() {
        coreDataManager = nil
        super.tearDown()
    }

    func testVeryRecentReadingUsesOlderTrendReading() {
        let current = reading(value: 101, secondsAgo: 0)
        let outOfTurnReading = reading(value: 98, secondsAgo: 20)
        let trendReading = reading(value: 97, secondsAgo: 5 * 60)

        let (slope, hideSlope) = current.calculateSlope(lastBgReadings: [outOfTurnReading, trendReading])
        current.calculatedValueSlope = slope
        current.hideSlope = hideSlope

        XCTAssertFalse(hideSlope)
        XCTAssertEqual(slope * 60_000, 0.8, accuracy: 0.001)
        XCTAssertEqual(current.slopeArrow(), "→")
    }

    func testTrendIsHiddenWhenOnlyVeryRecentReadingExists() {
        let current = reading(value: 101, secondsAgo: 0)
        let outOfTurnReading = reading(value: 98, secondsAgo: 20)

        let (slope, hideSlope) = current.calculateSlope(lastBgReadings: [outOfTurnReading])

        XCTAssertEqual(slope, 0)
        XCTAssertTrue(hideSlope)
    }

    func testNearestReadingWithEnoughElapsedTimeIsUsed() {
        let current = reading(value: 101, secondsAgo: 0)
        let olderReading = reading(value: 91, secondsAgo: 10 * 60)
        let nearestTrendReading = reading(value: 97, secondsAgo: 5 * 60)

        let (slope, hideSlope) = current.calculateSlope(lastBgReadings: [olderReading, nearestTrendReading])

        XCTAssertFalse(hideSlope)
        XCTAssertEqual(slope * 60_000, 0.8, accuracy: 0.001)
    }

    func testTrendIsHiddenAcrossLongReadingGap() {
        let current = reading(value: 101, secondsAgo: 0)
        let oldReading = reading(value: 97, secondsAgo: 22 * 60)

        let (slope, hideSlope) = current.calculateSlope(lastBgReadings: [oldReading])

        XCTAssertEqual(slope, 0)
        XCTAssertTrue(hideSlope)
    }

    func testSensorTrendOverridesCalculatedSlopeForDisplayAndGarmin() {
        let current = reading(value: 101, secondsAgo: 0)
        current.calculatedValueSlope = 0.8 / 60_000 // calculated trend would be flat
        current.sensorTrendOrdinal = NSNumber(value: 7) // G7 reports rapid fall
        current.hideSlope = false

        XCTAssertEqual(current.slopeOrdinal(), 7)
        XCTAssertEqual(current.slopeArrow(), "↓↓")
        XCTAssertEqual(current.slopeName, "DoubleDown")
        XCTAssertEqual(G7SensorTrend.arrow(ordinal: current.slopeOrdinal()), "↓↓")
    }

    func testMissingG7TrendNeverLooksFlat() {
        let current = reading(value: 101, secondsAgo: 0)
        current.sensorTrendOrdinal = NSNumber(value: 0)
        current.hideSlope = true

        XCTAssertEqual(current.slopeOrdinal(), 0)
        XCTAssertEqual(current.slopeArrow(), "")
        XCTAssertEqual(current.slopeName, "NOT COMPUTABLE")
    }

    func testBothV32VariantsCanMigrateToV33() throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: ConstantsCoreData.modelName, withExtension: "momd"))
        let v33 = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("xdrip v33.mom")))
        for sourceName in ["xdrip v31", "xdrip v32", "xdrip v32-garmin"] {
            let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("\(sourceName).mom")))
            XCTAssertNoThrow(try NSMappingModel.inferredMappingModel(forSourceModel: source, destinationModel: v33))
        }
        XCTAssertNotNil(v33.entitiesByName["BgReading"]?.attributesByName["sensorTrendOrdinal"])
    }

    private func reading(value: Double, secondsAgo: TimeInterval) -> BgReading {
        let bgReading = BgReading(timeStamp: now.addingTimeInterval(-secondsAgo), sensor: nil, calibration: nil, rawData: value, deviceName: nil, nsManagedObjectContext: coreDataManager.mainManagedObjectContext)
        bgReading.calculatedValue = value
        return bgReading
    }
}
