//
//  FetchedCollectionViewDataSource.swift
//  PeakCoreData
//
//  Created by David Yates on 07/03/2018.
//  Copyright © 2018 3Squared Ltd. All rights reserved.
//

import UIKit
import CoreData

public protocol FetchedCollectionViewDataSourceDelegate: CollectionViewUpdatable, HasEmptyView {
    associatedtype Header: UICollectionReusableView
    associatedtype Footer: UICollectionReusableView
    var headerReuseIdentifier: String? { get }
    var footerReuseIdentifier: String? { get }
    func configureHeader(_ header: Header, at indexPath: IndexPath)
    func configureFooter(_ footer: Footer, at indexPath: IndexPath)
}

public extension FetchedCollectionViewDataSourceDelegate {
    public var headerReuseIdentifier: String? { return nil }
    public var footerReuseIdentifier: String? { return nil }
    public func configureHeader(_ header: UICollectionReusableView, at indexPath: IndexPath) { }
    public func configureFooter(_ footer: UICollectionReusableView, at indexPath: IndexPath) { }
}

public class FetchedCollectionViewDataSource<Delegate: FetchedCollectionViewDataSourceDelegate>: NSObject, UICollectionViewDataSource, NSFetchedResultsControllerDelegate {
    public typealias Object = Delegate.Object
    public typealias Cell = Delegate.Cell
    public typealias Header = Delegate.Header
    public typealias Footer = Delegate.Footer

    private let collectionView: UICollectionView
    private let dataProvider: FetchedDataProvider<FetchedCollectionViewDataSource>
    private weak var delegate: Delegate!
    
    public var animateUpdates: Bool = true
    public var onDidChangeContent: (() -> Void)?
    
    public var cacheName: String? {
        return dataProvider.cacheName
    }
    
    public var fetchedObjectsCount: Int {
        return dataProvider.fetchedObjectsCount
    }
    
    public var isEmpty: Bool {
        return dataProvider.isEmpty
    }
    
    public var numberOfSections: Int {
        return dataProvider.numberOfSections
    }
    
    public var sectionIndexTitles: [String] {
        return dataProvider.sectionIndexTitles
    }
    
    public var sectionNameKeyPath: String? {
        return dataProvider.sectionNameKeyPath
    }
    
    public required init(collectionView: UICollectionView, fetchedResultsController: NSFetchedResultsController<Object>, delegate: Delegate) {
        self.collectionView = collectionView
        self.delegate = delegate
        self.dataProvider = FetchedDataProvider(fetchedResultsController: fetchedResultsController)
        super.init()
        collectionView.dataSource = self
        dataProvider.delegate = self
    }
    
    public func indexPath(forObject object: Object) -> IndexPath? {
        return dataProvider.indexPath(forObject: object)
    }
    
    public func name(in section: Int) -> String? {
        return dataProvider.name(in: section)
    }
    
    public func numberOfItems(in section: Int) -> Int {
        return dataProvider.numberOfItems(in: section)
    }
    
    public func object(at indexPath: IndexPath) -> Object {
        return dataProvider.object(at: indexPath)
    }
    
    public func performFetch() {
        dataProvider.performFetch()
    }
    
    public func section(forSectionIndexTitle title: String, at index: Int) -> Int {
        return dataProvider.section(forSectionIndexTitle: title, at: index)
    }
    
    public func sectionInfo(forSection section: Int) -> NSFetchedResultsSectionInfo {
        return dataProvider.sectionInfo(forSection: section)
    }
    
    public func reconfigureFetchRequest(_ configure: (NSFetchRequest<Object>) -> ()) {
        dataProvider.reconfigureFetchRequest(configure)
    }
    
    public func showEmptyViewIfNeeded() {
        if isEmpty, let emptyView = delegate.emptyView {
            collectionView.backgroundView = emptyView
        } else {
            collectionView.backgroundView = nil
        }
    }
    
    // MARK: UICollectionViewDataSource
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return numberOfSections
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return numberOfItems(in: section)
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: delegate.cellReuseIdentifier, for: indexPath) as? Cell else {
            fatalError("Unexpected cell type at \(indexPath)")
        }
        delegate.configure(cell, with: object(at: indexPath))
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionHeader:
            guard let reuseIdentifier = delegate.headerReuseIdentifier else {
                fatalError("Missing reuse identifier for header at \(indexPath)")
            }
            guard let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as? Header else {
                fatalError("Unexpected header type at \(indexPath)")
            }
            delegate.configureHeader(header, at: indexPath)
            return header
        case UICollectionView.elementKindSectionFooter:
            guard let reuseIdentifier = delegate.footerReuseIdentifier else {
                fatalError("Missing reuse identifier for footer at \(indexPath)")
            }
            guard let footer = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as? Footer else {
                fatalError("Unexpected footer type at \(indexPath)")
            }
            delegate.configureFooter(footer, at: indexPath)
            return footer
        default:
            return UICollectionReusableView()
        }
    }
}

extension FetchedCollectionViewDataSource: FetchedDataProviderDelegate {
    
    func dataProviderDidUpdate(updates: [FetchedUpdate<Delegate.Object>]?) {
        guard let updates = updates, animateUpdates, collectionView.window != nil else {
            collectionView.reloadData()
            showEmptyViewIfNeeded()
            onDidChangeContent?()
            return
        }
        
        delegate.process(updates: updates, for: collectionView) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.showEmptyViewIfNeeded()
            strongSelf.onDidChangeContent?()
        }
    }
}
