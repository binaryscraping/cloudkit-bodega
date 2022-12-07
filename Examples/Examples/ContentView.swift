//
//  ContentView.swift
//  Examples
//
//  Created by Guilherme Souza on 07/12/22.
//

import SwiftUI
import SwiftUINavigation
import Boutique

struct ContentView: View {
  @ObservedObject var accounts: Store<Account>

  enum Route {
    case add(Account)
  }

  @State private var route: Route?

  var body: some View {
    NavigationStack {
      List {
        ForEach(accounts.items) { account in
          LabeledContent("Name", value: account.name)
        }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            route = .add(Account(id: UUID(), name: "", balance: 0, createdAt: Date()))
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
    }
    .sheet(unwrapping: $route, case: /Route.add) { $account in
      NavigationStack {
        Form {
          TextField("Name", text: $account.name)
        }
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              Task { @MainActor in
                try! await accounts.insert(account)
                route = nil
              }
            }
          }

          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
              route = nil
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
    ContentView(accounts: .previewStore(items: [], cacheIdentifier: \.id.uuidString))
  }
}
