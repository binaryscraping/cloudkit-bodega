//
//  ContentView.swift
//  Examples
//
//  Created by Guilherme Souza on 07/12/22.
//

import SwiftUI
import SwiftUINavigation
import Boutique

final class ViewModel: ObservableObject {
  enum Route {
    case add(Account)
  }

  @Published var route: Route?
  @Stored(in: .accounts) private var _accounts

  @MainActor var accounts: [Account] {
    _accounts.sorted(using: KeyPathComparator(\.createdAt, order: .reverse))
  }

  init(route: Route? = nil, accounts: Store<Account> = .accounts) {
    self.route = route
    __accounts = Stored(in: accounts)
  }

  func addButtonTapped() {
    route = .add(.init(id: UUID(), name: "", balance: 0, createdAt: Date()))
  }

  func confirmAddButtonTapped() {
    Task { @MainActor in
      guard case let .add(account) = route else {
        return
      }

      try! await $_accounts.insert(account)
      route = nil
    }
  }

  func cancelAddButtonTapped() {
    route = nil
  }
}

struct ContentView: View {
  @ObservedObject var viewModel: ViewModel

  var body: some View {
    NavigationStack {
      List {
        ForEach(viewModel.accounts) { account in
          LabeledContent("Name", value: account.name)
        }
      }
      .animation(.default, value: viewModel.accounts)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            viewModel.addButtonTapped()
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
    }
    .sheet(unwrapping: $viewModel.route, case: /ViewModel.Route.add) { $account in
      NavigationStack {
        EditAccountView(account: $account)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              viewModel.confirmAddButtonTapped()
            }
          }

          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
              viewModel.cancelAddButtonTapped()
            }
          }
        }
      }
      .padding()
      .frame(minWidth: 300)
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView(viewModel: ViewModel(accounts: .previewStore(items: [], cacheIdentifier: \.id.uuidString)))
  }
}
