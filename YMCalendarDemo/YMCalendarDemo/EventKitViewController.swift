//
//  EventKitViewController.swift
//  YMCalendarDemo
//
//  Created by Yuma Matsune on 2017/03/14.
//  Copyright © 2017年 Yuma Matsune. All rights reserved.
//

import Foundation
import UIKit
import YMCalendar
import EventKit

final class EventKitViewController: UIViewController {

    @IBOutlet weak var calendarView: YMCalendarView!
    
    let eventKitManager = EventKitManager()
    
    var cachedMonths: [Date : [Date : [EKEvent]]] = [:]
    
    var datesForMonthsToLoad: [Date] = []
    
    var movedEvent: EKEvent?
    
    var calendar: Calendar = .current {
        didSet {
            calendarView.calendar = calendar
        }
    }
    
    var bgQueue = DispatchQueue(label: "EventKitViewController.bgQueue")
    
    var visibleCalendars: [EKCalendar] = [] {
        didSet {
            calendarView.reloadEvents()
        }
    }
    
    var visibleMonthsRange: DateRange? {
        return calendarView.visibleMonthRange
    }
    
    var visibleMonths: DateRange = DateRange()
    
    var eventStore: EKEventStore {
        return eventKitManager.eventStore
    }
    
    let EventCellReuseIdentifier = "EventCellReuseIdentifier"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        calendarView.delegate = self
        calendarView.dataSource = self
        calendarView.registerClass(YMEventStandardView.self, forEventCellReuseIdentifier: EventCellReuseIdentifier)
        
        eventKitManager.checkEventStoreAccessForCalendar { [weak self] granted in
            if granted {
                if let calendars = self?.eventStore.calendars(for: .event) {
                    self?.visibleCalendars = calendars
                }
                self?.reloadEvents()
            }
        }
    }
    
    func reloadEvents() {
        cachedMonths.removeAll()
        loadEventsIfNeeded()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadEventsIfNeeded()
    }
    
    func fetchEvents(from startDate: Date, to endDate: Date, calendars: [EKCalendar]?) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        if eventKitManager.accessGranted {
            let events = eventStore.events(matching: predicate)
            return events
        }
        return []
    }
    
    func allEventsInDateRange(_ range: DateRange) -> [Date : [EKEvent]] {
        let events = fetchEvents(from: range.start, to: range.end, calendars: nil)
        
        var eventsPerDay: [Date : [EKEvent]] = [:]
        for event in events {
            let start = calendar.startOfDay(for: event.startDate)
            let eventRange = DateRange(start: start, end: event.endDate)
            
            eventRange.enumerateDaysWithCalendar(calendar, usingBlock: { date, stop in
                if eventsPerDay[date] == nil {
                    eventsPerDay[date] = []
                }
                eventsPerDay[date]?.append(event)
            })
        }
        return eventsPerDay
    }
    
    func bg_loadMonthStartingAtDate(_ date: Date) {
        let end = calendar.nextStartOfMonthForDate(date)
        let range = DateRange(start: date, end: end)
        let dic = allEventsInDateRange(range)
        DispatchQueue.main.async {
            self.cachedMonths[date] = dic
            
            let rangeEnd = self.calendar.nextStartOfMonthForDate(date)
            let range = DateRange(start: date, end: rangeEnd)
            self.calendarView.reloadEventsInRange(range)
        }
    }
    
    func bg_loadOneMonth() {
        var date: Date? = nil
        DispatchQueue.main.sync {
            if let d = datesForMonthsToLoad.first {
                date = d
                datesForMonthsToLoad.removeFirst()
            }
            if let visibleDays = calendarView.visibleDays,
                !visibleDays.intersectsDateRange(visibleMonths) {
                date = nil
            }
        }
        if let date = date {
            bg_loadMonthStartingAtDate(date)
        }
    }
    
    func addMonthToLoadingQueue(monthStart: Date) {
        datesForMonthsToLoad.append(monthStart)
        
        bgQueue.async {
            self.bg_loadOneMonth()
        }
    }
    
    func loadEventsIfNeeded() {
        datesForMonthsToLoad.removeAll()
        
        guard let visibleMonthsRange = visibleMonthsRange,
            let months = visibleMonthsRange.components([.month], forCalendar: calendar).month else {
            return
        }
        for i in 0..<(months+1) {
            var dc = DateComponents()
            dc.month = i
            if let date = calendar.date(byAdding: dc, to: visibleMonthsRange.start) {
                if cachedMonths[date] == nil {
                    addMonthToLoadingQueue(monthStart: date)
                }
            }
        }
    }
    
    func eventsAtDate(_ date: Date) -> [EKEvent] {
        let firstOfMonth = calendar.startOfMonthForDate(date)
        if let days = cachedMonths[firstOfMonth] {
            if let events = days[date] {
                return events
            }
        }
        return []
    }
}

extension EventKitViewController: YMCalendarDelegate {
    func calendarView(_ view: YMCalendarView, didSelectDayCellAtDate date: Date) {
        print(view.visibleDays)
    }
    
    func calendarViewDidScroll(_ view: YMCalendarView) {
        if let visibleMonthsRange = visibleMonthsRange, visibleMonths != visibleMonthsRange {
            self.visibleMonths = visibleMonthsRange
            self.loadEventsIfNeeded()
        }
    }
    
    func monthView(_ view: YMCalendarView, didDeselectEventAtIndex index: Int, date: Date) {
        if let cell = view.cellForEventAtIndex(index, date: date) {
            let rect = view.convert(cell.bounds, from: cell)
            print(rect)
        }
    }
    
    func calendarView(_ view: YMCalendarView, didShowDate date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY/MM/dd"
        navigationItem.title = formatter.string(from: date)
    }
}

extension EventKitViewController: YMCalendarDataSource {
    func calendarView(_ view: YMCalendarView, numberOfEventsAtDate date: Date) -> Int {
        return eventsAtDate(date).count
    }
    
    func calendarView(_ view: YMCalendarView, dateRangeForEventAtIndex index: Int, date: Date) -> DateRange? {
        let events = eventsAtDate(date)
        var range: DateRange? = nil
        if index <= events.count {
            let event = events[index]
            range = DateRange(start: event.startDate, end: event.endDate)
        }
        return range
    }
    
    func calendarView(_ view: YMCalendarView, cellForEventAtIndex index: Int, date: Date) -> YMEventView {
        let events = eventsAtDate(date)
        var cell: YMEventStandardView? = nil
        if index <= events.count {
            let event = events[index]
            cell = view.dequeueReusableCellWithIdentifier(EventCellReuseIdentifier, forEventAtIndex: index, date: date)
            cell?.title = event.title
            cell?.color = UIColor.init(cgColor: event.calendar.cgColor)
            
//            let start = calendar.startOfDay(for: event.startDate)
//            let end = calendar.nextStartOfMonthForDate(event.endDate)
//            let range = DateRange(start: start, end: end)
//            let numDays = range.components([.day], forCalendar: calendar)
        }
        return cell ?? YMEventStandardView()
    }
    
    func calendarView(_ view: YMCalendarView, canMoveCellForEventAtIndex index: Int, date: Date) -> Bool {
//        let events = eventsAtDate(date)
        return false
    }
    
    func calendarView(_ view: YMCalendarView, cellForNewEventAtDate date: Date) -> YMEventView {
        let defaultCalendar = eventStore.defaultCalendarForNewEvents
        
        let cell = YMEventStandardView()
        cell.title = "New Event"
        
        return cell
    }
}
