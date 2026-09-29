import Foundation

/// Visits each field of a moment that can be edited, by its key in the file.
protocol MomentFieldVisitor {
    /// - Parameter precedes: A total order on the field's values, to break ties the same way on
    ///   every Mac.
    mutating func visit<Value: Equatable>(
        _ key: String, _ field: WritableKeyPath<Moment, Value>, precedes: (Value, Value) -> Bool)
}

extension Moment {
    /// Every field that can be edited, and so can change on one Mac independently of another.
    /// The id and the timestamps aren't; unknown keys (`extras`) travel as one.
    static func visitFields(_ visitor: inout some MomentFieldVisitor) {
        visitor.visit("kind", \.kind) { $0.rawValue < $1.rawValue }
        visitor.visit("name", \.name, precedes: <)
        visitor.visit("emoji", \.emoji, precedes: <)
        visitor.visit("imageData", \.imageData) { a, b in
            switch (a, b) {
            case (nil, _?): true
            case (let a?, let b?): a.lexicographicallyPrecedes(b)
            default: false
            }
        }
        visitor.visit("color", \.colorHex, precedes: <)
        visitor.visit("date", \.date, precedes: <)
        visitor.visit("startDate", \.startDate, precedes: <)
        visitor.visit("endDate", \.endDate, precedes: <)
        visitor.visit("span", \.span) { $0.rawValue < $1.rawValue }
        visitor.visit("unit", \.unit) { $0.rawValue < $1.rawValue }
        visitor.visit("repeatCycle", \.repeatCycle) { $0.rawValue < $1.rawValue }
        visitor.visit("remindDays", \.remindDays, precedes: <)
        visitor.visit("inMenubar", \.inMenubar) { !$0 && $1 }
        visitor.visit("sortWeight", \.sortWeight, precedes: <)
    }

    /// When the field with `key` last changed.
    ///
    /// A field this app hasn't changed since the moment was created dates from `createdAt`. If
    /// `updatedAt` is later than every field's time, something that doesn't keep them (the
    /// original app) edited the moment, and since it's unknown which fields it changed, they all
    /// count as changed then.
    public func stamp(of key: String) -> Date {
        let latest = fieldUpdatedAt.values.reduce(createdAt, max)
        if updatedAt > latest {
            return updatedAt
        }
        return fieldUpdatedAt[key] ?? createdAt
    }

    /// The keys of the fields that differ between the two.
    func changedFields(from other: Moment) -> Set<String> {
        struct Differ: MomentFieldVisitor {
            let a: Moment, b: Moment
            var keys: Set<String> = []
            mutating func visit<Value: Equatable>(
                _ key: String, _ field: WritableKeyPath<Moment, Value>, precedes: (Value, Value) -> Bool
            ) {
                if a[keyPath: field] != b[keyPath: field] {
                    keys.insert(key)
                }
            }
        }
        var differ = Differ(a: self, b: other)
        Self.visitFields(&differ)
        return differ.keys
    }

    /// Copies the fields with `keys` from `source`, each changed at `stamp`.
    mutating func take(_ keys: Set<String>, from source: Moment, at stamp: Date) {
        struct Copier: MomentFieldVisitor {
            let source: Moment, keys: Set<String>, stamp: Date
            var target: Moment
            mutating func visit<Value: Equatable>(
                _ key: String, _ field: WritableKeyPath<Moment, Value>, precedes: (Value, Value) -> Bool
            ) {
                guard keys.contains(key) else { return }
                target[keyPath: field] = source[keyPath: field]
                target.unparsed[key] = nil
                target.fieldUpdatedAt[key] = stamp
            }
        }
        // Spell out every field's time first: once one field has its own, the others can no
        // longer be told apart from it by `updatedAt` alone.
        fieldUpdatedAt = explicitStamps()
        var copier = Copier(source: source, keys: keys, stamp: stamp, target: self)
        Self.visitFields(&copier)
        self = copier.target
        updatedAt = max(updatedAt, stamp)
    }

    /// ``stamp(of:)`` for each field changed since the moment was created.
    func explicitStamps() -> [String: Date] {
        struct Stamper: MomentFieldVisitor {
            let moment: Moment
            var stamps: [String: Date] = [:]
            mutating func visit<Value: Equatable>(
                _ key: String, _ field: WritableKeyPath<Moment, Value>, precedes: (Value, Value) -> Bool
            ) {
                let stamp = moment.stamp(of: key)
                if stamp > moment.createdAt {
                    stamps[key] = stamp
                }
            }
        }
        var stamper = Stamper(moment: self)
        Self.visitFields(&stamper)
        return stamper.stamps
    }

    /// Combines two versions of this moment field by field: each field takes the value that
    /// changed last. It doesn't matter which version is which, or in what order versions from
    /// several Macs are combined; the result is the same.
    static func merged(_ a: Moment, _ b: Moment) -> Moment {
        if a == b { return a }
        struct Merger: MomentFieldVisitor {
            let a: Moment, b: Moment
            var result: Moment
            var stamps: [String: Date] = [:]
            mutating func visit<Value: Equatable>(
                _ key: String, _ field: WritableKeyPath<Moment, Value>, precedes: (Value, Value) -> Bool
            ) {
                let stampA = a.stamp(of: key)
                let stampB = b.stamp(of: key)
                let valueA = a[keyPath: field]
                let valueB = b[keyPath: field]
                let takeB = stampA != stampB ? stampB > stampA : valueA != valueB && precedes(valueA, valueB)
                let source = takeB ? b : a
                result[keyPath: field] = source[keyPath: field]
                result.unparsed[key] = source.unparsed[key]
                stamps[key] = max(stampA, stampB)
            }
        }
        var merger = Merger(a: a, b: b, result: a)
        visitFields(&merger)
        var result = merger.result
        result.createdAt = min(a.createdAt, b.createdAt)
        result.updatedAt = max(a.updatedAt, b.updatedAt)
        result.fieldUpdatedAt = merger.stamps.filter { $0.value > result.createdAt }
        result.extras = newer(a, b).extras
        return result
    }

    /// The more recently updated of two versions. A tie is broken by content, so every Mac
    /// picks the same one.
    static func newer(_ a: Moment, _ b: Moment) -> Moment {
        if a.updatedAt != b.updatedAt {
            return a.updatedAt > b.updatedAt ? a : b
        }
        return a.canonicalData.lexicographicallyPrecedes(b.canonicalData) ? b : a
    }
}
