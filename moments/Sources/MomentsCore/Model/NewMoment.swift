import Foundation

extension Moment {
    /// A moment of `kind` as it starts out when it's added at `now`: on today, or for a progress
    /// bar, through this year, with custom dates from today to a month later.
    public init(new kind: Kind, at now: Date, sortWeight: Int = 0, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        self.init(
            kind: kind, date: kind == .progress ? now : today, startDate: today,
            endDate: kind == .progress ? calendar.date(byAdding: .month, value: 1, to: today) : nil,
            sortWeight: sortWeight, createdAt: now)
    }

    /// Starts this unsaved moment over as a `kind`, as if it had been added as one. What every
    /// kind has (the name, emoji, photo, color, and menu bar item) stays as people set it, so
    /// changing their mind about the kind doesn't cost them those.
    public mutating func switchKind(to kind: Kind, calendar: Calendar = .current) {
        var moment = Moment(new: kind, at: createdAt, sortWeight: sortWeight, calendar: calendar)
        moment.id = id
        moment.name = name
        moment.emoji = emoji
        moment.imageData = imageData
        moment.colorHex = colorHex
        moment.inMenubar = inMenubar
        self = moment
    }
}
