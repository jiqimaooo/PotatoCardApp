import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    private static let storageKey = "todoItems"

    @Published private(set) var items: [TodoItem] = [] {
        didSet {
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.items = Self.load(from: userDefaults)
    }

    private let userDefaults: UserDefaults

    func add(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        items.append(TodoItem(title: trimmedTitle))
    }

    func update(_ item: TodoItem, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].title = trimmedTitle
        items[index].updatedAt = Date()
    }

    func toggleDone(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].isDone.toggle()
        items[index].updatedAt = Date()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
    }

    func clearAll() {
        items.removeAll()
    }

    func move(from source: IndexSet, to destination: Int) {
        let movingItems = source.sorted().compactMap { index in
            items.indices.contains(index) ? items[index] : nil
        }
        guard !movingItems.isEmpty else { return }

        for index in source.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let adjustedDestination = min(
            max(destination - removedBeforeDestination, 0),
            items.count
        )
        items.insert(contentsOf: movingItems, at: adjustedDestination)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from userDefaults: UserDefaults) -> [TodoItem] {
        guard let data = userDefaults.data(forKey: storageKey),
              let decodedItems = try? JSONDecoder().decode([TodoItem].self, from: data)
        else {
            return []
        }

        return decodedItems
    }
}
