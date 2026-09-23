import CoreData
import Foundation

let oldURL = URL(fileURLWithPath: CommandLine.arguments[1])
let newURL = URL(fileURLWithPath: CommandLine.arguments[2])
let storeURL = URL(fileURLWithPath: CommandLine.arguments[3])
let sourceName = CommandLine.arguments[4]
guard let oldModel = NSManagedObjectModel(contentsOf: oldURL),
      let newModel = NSManagedObjectModel(contentsOf: newURL),
      let oldReading = oldModel.entitiesByName["BgReading"],
      let newReading = newModel.entitiesByName["BgReading"],
      newReading.attributesByName["sensorTrendOrdinal"]?.isOptional == true else {
    fatalError("G7 trend model versions are not compatible")
}
let oldTrend = oldReading.attributesByName["sensorTrendOrdinal"] == nil ? nil : NSNumber(value: 3)

_ = try NSMappingModel.inferredMappingModel(forSourceModel: oldModel, destinationModel: newModel)

let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                                      configurationName: nil,
                                                      at: storeURL)
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = oldCoordinator
let reading = NSManagedObject(entity: oldReading, insertInto: context)
for key in ["a", "ageAdjustedRawValue", "b", "c", "calculatedValueSlope", "ra", "rb", "rc"] {
    reading.setValue(0.0, forKey: key)
}
reading.setValue("old-reading", forKey: "id")
reading.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "timeStamp")
reading.setValue(120.0, forKey: "calculatedValue")
reading.setValue(120.0, forKey: "rawData")
reading.setValue(false, forKey: "calibrationFlag")
reading.setValue(false, forKey: "hideSlope")
reading.setValue(false, forKey: "isSuppressedByFiveMinuteCadence")
if let oldTrend {
    reading.setValue(oldTrend, forKey: "sensorTrendOrdinal")
}
try context.save()
try oldCoordinator.remove(oldStore)

let newCoordinator = NSPersistentStoreCoordinator(managedObjectModel: newModel)
_ = try newCoordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                          configurationName: nil,
                                          at: storeURL,
                                          options: [NSMigratePersistentStoresAutomaticallyOption: true,
                                                    NSInferMappingModelAutomaticallyOption: true])
let migratedContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
migratedContext.persistentStoreCoordinator = newCoordinator
let request = NSFetchRequest<NSManagedObject>(entityName: "BgReading")
guard let migrated = try migratedContext.fetch(request).first,
      migrated.value(forKey: "id") as? String == "old-reading",
      migrated.value(forKey: "calculatedValue") as? Double == 120,
      migrated.value(forKey: "sensorTrendOrdinal") as? NSNumber == oldTrend else {
    fatalError("previous glucose reading did not survive migration")
}
print("G7 Core Data \(sourceName) → v33 migration: passed")
