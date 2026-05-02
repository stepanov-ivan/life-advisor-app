import Foundation
import SwiftData

enum FoodDatabaseSeeder {
    struct FoodEntry: Codable {
        let name: String
        let category: String
        let calories: Double
        let proteins: Double
        let fats: Double
        let carbs: Double
        let fiber: Double
    }

    static func seed(into context: ModelContext) {
        let entries: [FoodEntry]
        if let url = Bundle.main.url(forResource: "food_database", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([FoodEntry].self, from: data) {
            entries = parsed
        } else {
            entries = sampleData()
        }

        for entry in entries {
            let item = FoodItem(
                name: entry.name,
                category: entry.category,
                calories: entry.calories,
                proteins: entry.proteins,
                fats: entry.fats,
                carbs: entry.carbs,
                fiber: entry.fiber
            )
            context.insert(item)
        }

        try? context.save()
    }

    static func sampleData() -> [FoodEntry] {
        [
            FoodEntry(name: "овсянка", category: "крупы", calories: 342, proteins: 12, fats: 6, carbs: 60, fiber: 8),
            FoodEntry(name: "гречка", category: "крупы", calories: 343, proteins: 13, fats: 3, carbs: 72, fiber: 10),
            FoodEntry(name: "рис белый", category: "крупы", calories: 344, proteins: 7, fats: 1, carbs: 79, fiber: 0.4),
            FoodEntry(name: "макароны отварные", category: "крупы", calories: 131, proteins: 5, fats: 1, carbs: 25, fiber: 1.8),
            FoodEntry(name: "куриная грудка", category: "мясо", calories: 165, proteins: 31, fats: 3.6, carbs: 0, fiber: 0),
            FoodEntry(name: "говядина", category: "мясо", calories: 250, proteins: 26, fats: 16, carbs: 0, fiber: 0),
            FoodEntry(name: "свинина", category: "мясо", calories: 259, proteins: 16, fats: 22, carbs: 0, fiber: 0),
            FoodEntry(name: "яйцо куриное", category: "мясо", calories: 155, proteins: 13, fats: 11, carbs: 0.7, fiber: 0),
            FoodEntry(name: "лосось", category: "мясо", calories: 208, proteins: 20, fats: 13, carbs: 0, fiber: 0),
            FoodEntry(name: "творог 5%", category: "молочка", calories: 145, proteins: 17, fats: 5, carbs: 3, fiber: 0),
            FoodEntry(name: "молоко 2.5%", category: "молочка", calories: 52, proteins: 2.8, fats: 2.5, carbs: 4.8, fiber: 0),
            FoodEntry(name: "сыр российский", category: "молочка", calories: 364, proteins: 23, fats: 30, carbs: 0, fiber: 0),
            FoodEntry(name: "йогурт натуральный", category: "молочка", calories: 63, proteins: 3.5, fats: 3.2, carbs: 5.7, fiber: 0),
            FoodEntry(name: "помидор", category: "овощи", calories: 18, proteins: 0.9, fats: 0.2, carbs: 3.9, fiber: 1.2),
            FoodEntry(name: "огурец", category: "овощи", calories: 15, proteins: 0.8, fats: 0.1, carbs: 2.8, fiber: 0.5),
            FoodEntry(name: "картофель", category: "овощи", calories: 77, proteins: 2, fats: 0.4, carbs: 16, fiber: 2.2),
            FoodEntry(name: "капуста белокочанная", category: "овощи", calories: 25, proteins: 1.3, fats: 0.1, carbs: 5.8, fiber: 2.5),
            FoodEntry(name: "морковь", category: "овощи", calories: 41, proteins: 0.9, fats: 0.2, carbs: 9.6, fiber: 2.8),
            FoodEntry(name: "яблоко", category: "фрукты", calories: 52, proteins: 0.3, fats: 0.2, carbs: 14, fiber: 2.4),
            FoodEntry(name: "банан", category: "фрукты", calories: 89, proteins: 1.1, fats: 0.3, carbs: 23, fiber: 2.6),
            FoodEntry(name: "апельсин", category: "фрукты", calories: 47, proteins: 0.9, fats: 0.1, carbs: 12, fiber: 2.4),
            FoodEntry(name: "виноград", category: "фрукты", calories: 69, proteins: 0.7, fats: 0.2, carbs: 18, fiber: 0.9),
            FoodEntry(name: "хлеб белый", category: "полуфабрикаты", calories: 265, proteins: 9, fats: 3, carbs: 49, fiber: 2.7),
            FoodEntry(name: "хлеб ржаной", category: "полуфабрикаты", calories: 259, proteins: 8.5, fats: 3.3, carbs: 48, fiber: 5.8),
            FoodEntry(name: "пицца пепперони", category: "полуфабрикаты", calories: 298, proteins: 12, fats: 14, carbs: 33, fiber: 2),
            FoodEntry(name: "сахар", category: "полуфабрикаты", calories: 387, proteins: 0, fats: 0, carbs: 100, fiber: 0),
            FoodEntry(name: "масло сливочное", category: "молочка", calories: 717, proteins: 0.9, fats: 81, carbs: 0.6, fiber: 0),
            FoodEntry(name: "масло подсолнечное", category: "полуфабрикаты", calories: 884, proteins: 0, fats: 100, carbs: 0, fiber: 0),
            FoodEntry(name: "кофе чёрный", category: "напитки", calories: 2, proteins: 0.1, fats: 0, carbs: 0, fiber: 0),
            FoodEntry(name: "чай зелёный", category: "напитки", calories: 1, proteins: 0.1, fats: 0, carbs: 0, fiber: 0),
            FoodEntry(name: "сок апельсиновый", category: "напитки", calories: 45, proteins: 0.7, fats: 0.2, carbs: 10, fiber: 0.2),
            FoodEntry(name: "миндаль", category: "фрукты", calories: 579, proteins: 21, fats: 50, carbs: 22, fiber: 12.5),
            FoodEntry(name: "грецкий орех", category: "фрукты", calories: 654, proteins: 15, fats: 65, carbs: 14, fiber: 6.7),
            FoodEntry(name: "арахис", category: "фрукты", calories: 567, proteins: 26, fats: 49, carbs: 16, fiber: 8.5),
            FoodEntry(name: "шоколад молочный", category: "полуфабрикаты", calories: 535, proteins: 7.6, fats: 30, carbs: 59, fiber: 3.4),
            FoodEntry(name: "мёд", category: "полуфабрикаты", calories: 304, proteins: 0.3, fats: 0, carbs: 82, fiber: 0.2),
            FoodEntry(name: "кетчуп", category: "полуфабрикаты", calories: 101, proteins: 1.8, fats: 0.4, carbs: 25, fiber: 0.4),
            FoodEntry(name: "майонез", category: "полуфабрикаты", calories: 680, proteins: 1, fats: 75, carbs: 3, fiber: 0),
            FoodEntry(name: "куриные котлеты", category: "полуфабрикаты", calories: 220, proteins: 18, fats: 12, carbs: 10, fiber: 1),
            FoodEntry(name: "пельмени", category: "полуфабрикаты", calories: 275, proteins: 12, fats: 14, carbs: 29, fiber: 1.5),
            FoodEntry(name: "грибы шампиньоны", category: "овощи", calories: 22, proteins: 3.1, fats: 0.3, carbs: 3.3, fiber: 1),
            FoodEntry(name: "лук репчатый", category: "овощи", calories: 40, proteins: 1.1, fats: 0.1, carbs: 9.3, fiber: 1.7),
            FoodEntry(name: "чеснок", category: "овощи", calories: 149, proteins: 6.4, fats: 0.5, carbs: 33, fiber: 2.1),
            FoodEntry(name: "арбуз", category: "фрукты", calories: 30, proteins: 0.6, fats: 0.2, carbs: 7.6, fiber: 0.4),
            FoodEntry(name: "груша", category: "фрукты", calories: 57, proteins: 0.4, fats: 0.1, carbs: 15, fiber: 3.1),
            FoodEntry(name: "сметана 15%", category: "молочка", calories: 162, proteins: 2.6, fats: 15, carbs: 4.2, fiber: 0),
            FoodEntry(name: "кефир 2.5%", category: "молочка", calories: 53, proteins: 2.9, fats: 2.5, carbs: 4, fiber: 0),
            FoodEntry(name: "колбаса варёная", category: "полуфабрикаты", calories: 257, proteins: 12, fats: 23, carbs: 2, fiber: 0),
            FoodEntry(name: "сосиски", category: "полуфабрикаты", calories: 266, proteins: 11, fats: 24, carbs: 1.5, fiber: 0),
            FoodEntry(name: "брокколи", category: "овощи", calories: 34, proteins: 2.8, fats: 0.4, carbs: 7.2, fiber: 2.6),
            FoodEntry(name: "свёкла", category: "овощи", calories: 43, proteins: 1.6, fats: 0.2, carbs: 9.6, fiber: 2.8),
            FoodEntry(name: "кабачок", category: "овощи", calories: 17, proteins: 0.6, fats: 0.3, carbs: 3.1, fiber: 1),
            FoodEntry(name: "баклажан", category: "овощи", calories: 25, proteins: 1, fats: 0.2, carbs: 5.9, fiber: 3)
        ]
    }
}
