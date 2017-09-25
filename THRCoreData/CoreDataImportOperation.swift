//
//  ImportManyOperation.swift
//  THRCoreData
//
//  Created by Ben Walker on 15/12/2016.
//  Copyright © 2016 3Squared Ltd. All rights reserved.
//

import Foundation
import CoreData
import THROperations
import THRResult

open class CoreDataImportOperation<Intermediate>: CoreDataOperation<Changeset>, ConsumesResult where
    Intermediate: ManagedObjectUpdatable,
    Intermediate: UniqueIdentifiable,
    Intermediate.ManagedObject: ManagedObjectType,
    Intermediate.ManagedObject: UniqueIdentifiable
{
    public var input: Result<[Intermediate]> = Result { throw ResultError.noResult }

    typealias ManagedObject = Intermediate.ManagedObject

    open override func performWork(inContext context: NSManagedObjectContext) {
        do {
            let intermediates = try input.resolve()
            
            ManagedObject.insertOrUpdate(intermediates: intermediates, inContext: context) { intermediate, managedObject in
                intermediate.updateProperties(on: managedObject)
            }
            
            ManagedObject.insertOrUpdate(intermediates: intermediates, inContext: context) { intermediate, managedObject in
                intermediate.updateRelationships(on: managedObject, withContext: context)
            }
            
            // We must do this in order to pass the IDs as a result, otherwise the objects
            // will have temporary IDs that cannot be used with another context.
            try context.obtainPermanentIDs(for: Array(context.insertedObjects))

            output = Result {
                let insertedIds = Set(context.insertedObjects.map { $0.objectID })
                let updatedIds = Set(context.updatedObjects.map { $0.objectID })
                let allIds = insertedIds.union(updatedIds)
                
                return Changeset(all: allIds,
                                 inserted: insertedIds,
                                 updated: updatedIds)
            }
            finishAndSave()
        } catch {
            output = Result { throw error }
            finish()
        }
    }
}


/// A struct containing the NSManagedObjectIDs of the objects affected by the import.
//  all: all objects touched by the operation
//  inserted: newly created objects
//  updated: objects that existed before the import that may have been modified
public struct Changeset {
    public let all: Set<NSManagedObjectID>
    public let inserted: Set<NSManagedObjectID>
    public let updated: Set<NSManagedObjectID>
}
