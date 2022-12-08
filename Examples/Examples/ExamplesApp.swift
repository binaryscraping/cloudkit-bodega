//
//  ExamplesApp.swift
//  Examples
//
//  Created by Guilherme Souza on 07/12/22.
//

import SwiftUI

@main
struct ExamplesApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView(viewModel: ViewModel())
    }
  }
}
