import Foundation

/// Presentation only: legacy SF Symbol metadata remains readable in existing backups.
enum MacCategoryEmoji {
    static let choices = ["🍽️", "☕️", "🍰", "🥡", "🛒", "🛍️", "🏠", "🚗", "🏥", "💊", "📚", "🎓", "👕", "🎮", "✈️", "🌴", "🎁", "💰", "💼", "🏦", "💳", "📈", "🎬", "🎵", "🐾", "🏋️", "💡", "📱", "🧾", "🪙", "❤️", "🏷️", "📊", "🧳", "🚇", "🚲", "🥗", "🍕", "🍜", "👨‍👩‍👧‍👦", "🏖️", "🎯"]
    static func isValid(_ value: String) -> Bool {
        value.count == 1 && value.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x7f) || $0.value == 0x20e3 }
    }
    static func fallback(symbol: String, name: String) -> String {
        let names = ["餐饮":"🍽️", "Dining":"🍽️", "购物":"🛍️", "Shopping":"🛍️", "日常生活":"🛒", "交通":"🚗", "住房":"🏠", "Housing":"🏠", "医疗健康":"🏥", "教育":"🎓", "娱乐":"🎮", "旅行":"✈️", "工资":"💰", "Salary":"💰", "总预算":"📊"]
        let symbols = ["fork.knife":"🍽️", "cup.and.saucer":"☕️", "birthday.cake":"🍰", "takeoutbag.and.cup.and.straw":"🥡", "cart":"🛒", "bag":"🛍️", "house":"🏠", "house.fill":"🏠", "car":"🚗", "car.fill":"🚗", "heart":"❤️", "heart.fill":"❤️", "cross.case.fill":"🏥", "book":"📚", "graduationcap.fill":"🎓", "gift":"🎁", "gift.fill":"🎁", "airplane":"✈️", "banknote":"💰", "banknote.fill":"💰", "chart.line.uptrend.xyaxis":"📈", "gamecontroller":"🎮", "gamecontroller.fill":"🎮", "palm.tree.fill":"🌴", "suitcase.fill":"🧳", "ellipsis":"🏷️", "tshirt.fill":"👕", "dollarsign.circle":"🪙"]
        return symbols[symbol] ?? names[name] ?? "🏷️"
    }
}
