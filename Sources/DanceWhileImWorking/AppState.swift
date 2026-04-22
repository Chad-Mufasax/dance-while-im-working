import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var isDancing: Bool = false
    @Published var autoPressEnter: Bool = false
    @Published var paused: Bool = false

    var lastAutoPressAt: Date?
}
