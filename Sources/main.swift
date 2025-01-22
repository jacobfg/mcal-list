import Foundation
import EventKit

setbuf(stdout, nil)
let a = CommandLine.arguments
let USE = """
mcal-list 1.0 - https://github.com/jacobfg/mcal-list
List calendar events for today and tomorrow in macOS/Calendar.app

Usage:
 mcal <cal-names> [items-to-display] [--json] [--max-title-length=<length>] [--condense]

Options:
 - <cal-names>: A comma-separated list of calendar names to filter on.
 - [items-to-display]: Optional. Limits the number of events displayed.
 - [--json]: Outputs events in JSON format.
 - [--max-title-length=<length>]: Optional. Trims event titles in plain text output.
 - [--condense]: Optional. Condense to one line (ignored for JSON output).
"""

if a.count < 2 {
    print(USE)
    exit(1)
}

// Parse arguments
let calendarNames = a[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
var itemsToDisplay = -1
var outputJSON = false
var maxTitleLength = Int.max
var condenseOutput = false

for arg in a.dropFirst(2) {
    if arg == "--json" {
        outputJSON = true
    } else if arg.starts(with: "--max-title-length=") {
        if let length = Int(arg.replacingOccurrences(of: "--max-title-length=", with: "")), length > 0 {
            maxTitleLength = length
        } else {
            print("Invalid value for --max-title-length")
            exit(1)
        }
    } else if arg.starts(with: "--condense") {
        condenseOutput = true // ignored for json
    } else if let n = Int(arg), n >= 0 {
        itemsToDisplay = n
    } else {
        print("Invalid argument: \(arg)")
        print(USE)
        exit(1)
    }
}

let eventStore = EKEventStore()

switch EKEventStore.authorizationStatus(for:.event){
  case .authorized:
    break
  case .denied:
    print("Settings > Privacy & Security > Calendars > Terminal")
    exit(1)
  case .notDetermined:
    eventStore.requestFullAccessToEvents(completion:{
        (granted:Bool,error:Error?)->Void in if granted{
            print("granted")
        } else {
            print("access denied")
        }
    })
  default:fputs("?",stderr)
}

let now = Date()
let startOfToday = Calendar.current.startOfDay(for: now)
let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday)!

let calendars = eventStore.calendars(for: .event).filter { calendarNames.contains($0.title) }

guard !calendars.isEmpty else {
    print("No matching calendars found for the provided names.")
    exit(1)
}

let eventsTodayAndTomorrow = eventStore.events(
    matching: eventStore.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: calendars)
).filter {
    !$0.isAllDay && $0.endDate > now && $0.endDate.timeIntervalSince($0.startDate) < 86400
}

// Deduplicate events based on UUID
var seenEventIdentifiers = Set<String>()
let deduplicatedEvents = eventsTodayAndTomorrow.filter { event in
    guard let identifier = event.eventIdentifier else { return true }
    if seenEventIdentifiers.contains(identifier) {
        return false
    } else {
        seenEventIdentifiers.insert(identifier)
        return true
    }
}

// Limit the number of events if specified
let limitedEvents = itemsToDisplay != -1 ? Array(eventsTodayAndTomorrow.prefix(itemsToDisplay)) : eventsTodayAndTomorrow

if outputJSON {
    // Convert events to JSON
    let eventsJSON = limitedEvents.map { event -> [String: Any] in
        [
            "uuid": event.eventIdentifier ?? "Unknown",
            "title": event.title ?? "No Title",
            "startDate": event.startDate?.fmt(f: "yyyy-MM-dd'T'HH:mm:ssZ") ?? "",
            "endDate": event.endDate?.fmt(f: "yyyy-MM-dd'T'HH:mm:ssZ") ?? "",
            "duration": event.endDate?.timeIntervalSince(event.startDate ?? Date()) ?? 0,
            "isAllDay": event.isAllDay
        ]
    }
    if let jsonData = try? JSONSerialization.data(withJSONObject: eventsJSON, options: .prettyPrinted),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    }
} else {
    for (i, event) in limitedEvents.enumerated() {
        let startTime = event.startDate?.fmt(f: "HH:mm") ?? "Unknown"
        let endTime = event.endDate?.fmt(f: "HH:mm") ?? "Unknown"
        let title = event.title ?? "No Title"
        let trimmedTitle = title.count > maxTitleLength
            ? String(title.prefix(maxTitleLength - 3)).trimTrailingWhiteSpace() + "..."
            : title
        if condenseOutput {
            if i > 0 {
                print(" | ", terminator: "")
            }
            print("\(startTime) \(trimmedTitle)", terminator: "")
        } else{
            print("\(startTime) - \(endTime): \(trimmedTitle)")
        }
    }
}

extension Date {
    func fmt(f: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = f
        return formatter.string(from: self)
    }
}

extension String {
   func trimTrailingWhiteSpace() -> String {
       guard self.last == " " else { return self }
    
       var tmp = self
       repeat {
           tmp = String(tmp.dropLast())
       } while tmp.last == " "
    
       return tmp
    }
}
