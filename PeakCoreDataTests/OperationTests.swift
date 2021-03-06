//
//  OperationTests.swift
//  PeakCoreData
//
//  Created by David Yates on 15/12/2016.
//  Copyright © 2016 3Squared Ltd. All rights reserved.
//

import XCTest
import CoreData
@testable
import PeakCoreData
import PeakResult

class OperationTests: CoreDataTests, NSFetchedResultsControllerDelegate {
    
    var operationQueue: OperationQueue {
        let queue = OperationQueue()
        return queue
    }
    
    func testAddOneOperation() {
        let expectedCount = 100
        let id = UUID().uuidString
        var previousOperation: AddOneOperation? = nil
        
        let finishExpectation = expectation(description: #function)

        for _ in 0..<expectedCount {
            let operation = AddOneOperation(uniqueKeyValue: id, persistentContainer: persistentContainer)
            if let previousOperation = previousOperation {
                operation.addDependency(previousOperation)
            }
            operationQueue.addOperation(operation)
            previousOperation = operation
        }
        
        var count = 0
        let finishOperation = BlockOperation {
            // Check that all the changes have made their way to the main context
            let objectToUpdate = TestEntity.fetchOrInsertObject(with: id, in: self.viewContext)
            count = Int(objectToUpdate.count)
            finishExpectation.fulfill()
        }
        
        finishOperation.addDependency(previousOperation!)
        operationQueue.addOperation(finishOperation)
        
        // THEN: then the main and background contexts are saved and the completion handler is called
        waitForExpectations(timeout: defaultTimeout, handler: { error in
            XCTAssertEqual(count, expectedCount)
        })
    }
    
    func testSingleImportOperation() {
        let numberOfInserts = 5
        let numberOfItems = 1
        var previousOperation: CoreDataSingleImportOperation<TestEntityJSON>? = nil
        let finishExpectation = expectation(description: #function)
        
        for _ in 0..<numberOfInserts {
            
            // Create intermediate objects
            let input = CoreDataTests.createTestIntermediateObjects(number: numberOfItems, in: viewContext)
            try! viewContext.save()
            
            // Create import operation with intermediates as input
            let operation = CoreDataSingleImportOperation<TestEntityJSON>(with: persistentContainer)
            operation.input = Result { input.first! }
            
            if let previousOperation = previousOperation {
                operation.addDependency(previousOperation)
            }
            
            operationQueue.addOperation(operation)
            previousOperation = operation
        }
        
        previousOperation?.addResultBlock { result in
            let count = TestEntity.count(in: self.viewContext)
            XCTAssertEqual(count, (numberOfInserts * numberOfItems))
            finishExpectation.fulfill()
        }
        
        // THEN: then the main and background contexts are saved and the completion handler is called
        waitForExpectations(timeout: defaultTimeout)
    }
    
    func testBatchImportOperation() {
        let numberOfInserts = 5
        let numberOfItems = 100
        var previousOperation: CoreDataBatchImportOperation<TestEntityJSON>? = nil

        let finishExpectation = expectation(description: #function)

        for _ in 0..<numberOfInserts {
        
            // Create intermediate objects
            let input = CoreDataTests.createTestIntermediateObjects(number: numberOfItems, in: viewContext)
            try! viewContext.save()
            
            
            // Create import operation with intermediates as input
            let operation = CoreDataBatchImportOperation<TestEntityJSON>(with: persistentContainer)
            operation.input = Result { input }
            
            if let previousOperation = previousOperation {
                operation.addDependency(previousOperation)
            }
            
            operationQueue.addOperation(operation)
            previousOperation = operation
        }
        
        previousOperation?.addResultBlock { result in
            let count = TestEntity.count(in: self.viewContext)
            XCTAssertEqual(count, (numberOfInserts * numberOfItems))
            finishExpectation.fulfill()
        }
        
        // THEN: then the main and background contexts are saved and the completion handler is called
        waitForExpectations(timeout: defaultTimeout)
    }
    
    func testBatchImportOutcomeNumbersAreCorrect() {
        let numberOfItems = 100
        let finishExpectation = expectation(description: #function)

        let input = CoreDataTests.createTestIntermediateObjects(number: numberOfItems, in: persistentContainer.viewContext)
        try! persistentContainer.viewContext.save()
        
        // Create import operation with intermediates as input
        let operation = CoreDataBatchImportOperation<TestEntityJSON>(with: persistentContainer)
        operation.input = Result { input }
        
        operation.addResultBlock { result in
            let outcome = try! result.resolve()
            outcome.inserted.forEach {
                XCTAssertFalse($0.isTemporaryID)
            }
            outcome.updated.forEach {
                XCTAssertFalse($0.isTemporaryID)
            }
            XCTAssertEqual(outcome.inserted.count, numberOfItems / 2)
            XCTAssertEqual(outcome.updated.count, numberOfItems / 2)
            XCTAssertEqual(outcome.all.count, numberOfItems)

            finishExpectation.fulfill()
        }
        
        operationQueue.addOperation(operation)
        waitForExpectations(timeout: defaultTimeout)
    }
    
    func testBatchImportTriggersFetchedResultsController() {
        let numberOfItems = 1000
        var intermediateItems: [TestEntityJSON] = []
        for item in 0..<numberOfItems {
            let id = UUID().uuidString
            let title = "Item " + String(item)
            let intermediate = TestEntityJSON(uniqueID: id, title: title)
            intermediateItems.append(intermediate)
        }
        let finishExpectation = expectation(description: #function)
        
        let fetchRequest = TestEntity.sortedFetchRequest()
        let frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: viewContext, sectionNameKeyPath: nil, cacheName: nil)
        
        let listener = FetchedResultsListener { (count) in
            XCTAssertEqual(count, numberOfItems)
            finishExpectation.fulfill()
        }
        
        frc.delegate = listener
        try! frc.performFetch()
        
        // Create import operation with intermediates as input
        let operation = CoreDataBatchImportOperation<TestEntityJSON>(with: persistentContainer)
        operation.input = Result { intermediateItems }
        
        operationQueue.addOperation(operation)
        waitForExpectations(timeout: defaultTimeout)
    }
    
    func testComplexSaveOperation() {
        let finishExpectation = expectation(description: #function)
        let insertCount = 100
        let deleteCount = 10
        let operation = InsertThenDeleteOperation(insertCount: insertCount, deleteCount: deleteCount, persistentContainer: persistentContainer)
        operation.addResultBlock { (result) in
            let outcome = try! result.resolve()
            XCTAssertEqual(outcome.inserted.count, insertCount-deleteCount)
            finishExpectation.fulfill()
        }
        operationQueue.addOperation(operation)
        waitForExpectations(timeout: defaultTimeout)
    }

}

class FetchedResultsListener: NSObject, NSFetchedResultsControllerDelegate {
    
    let completionBlock: (Int) -> Void
    
    init(completionBlock: @escaping (Int) -> Void) {
        self.completionBlock = completionBlock
        super.init()
    }
    
    var count = 0
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        count = 0
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        count += 1
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        completionBlock(count)
    }
}

class AddOneOperation: CoreDataOperation<Void> {
    
    let uniqueKeyValue: String

    init(uniqueKeyValue: String, persistentContainer: NSPersistentContainer) {
        self.uniqueKeyValue = uniqueKeyValue
        super.init(with: persistentContainer)
    }
    
    override func performWork(in context: NSManagedObjectContext) {
        let objectToUpdate = TestEntity.fetchOrInsertObject(with: uniqueKeyValue, in: context)
        objectToUpdate.count += 1
        saveAndFinish()
    }
}

class InsertThenDeleteOperation: CoreDataChangesetOperation {
    
    let insertCount: Int
    let deleteCount: Int
    
    init(insertCount: Int, deleteCount: Int, persistentContainer: NSPersistentContainer) {
        self.insertCount = insertCount
        self.deleteCount = deleteCount
        super.init(with: persistentContainer)
    }
    
    override func performWork(in context: NSManagedObjectContext) {
        var testEntities: [TestEntity] = []
        for item in 0..<insertCount {
            let id = UUID().uuidString
            let newObject = TestEntity.insertObject(with: id, in: context)
            newObject.title = "Item " + String(item)
            testEntities.append(newObject)
        }
        saveOperationContext()
        
        let toDelete = testEntities.prefix(deleteCount)
        toDelete.forEach { context.delete($0) }
        saveAndFinish()
    }
}

