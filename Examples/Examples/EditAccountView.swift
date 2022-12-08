import SwiftUI

struct EditAccountView: View {
  @Binding var account: Account

  var body: some View {
    Form {
      TextField("Name", text: $account.name)
    }
  }
}
