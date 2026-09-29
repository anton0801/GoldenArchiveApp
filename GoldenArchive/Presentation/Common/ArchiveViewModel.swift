//
//  ArchiveViewModel.swift
//  GoldenArchive
//
//  Presentation layer — base class for view models that rebuild their state
//  whenever the archive changes.
//

import Foundation
import Combine

@MainActor
class ArchiveViewModel: ObservableObject {
    let container: AppContainer
    private var changeSubscription: AnyCancellable?

    init(container: AppContainer) {
        self.container = container
        changeSubscription = container.changes.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
    }

    /// Recomputes published state from repositories. Subclasses override.
    func reload() {}

    var units: MeasurementUnits { container.settings.settings().units }
}
