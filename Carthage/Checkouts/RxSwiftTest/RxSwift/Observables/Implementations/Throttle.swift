//
//  Throttle.swift
//  Rx
//
//  Created by Krunoslav Zaher on 3/22/15.
//  Copyright (c) 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class ThrottleSink<O: ObserverType, SchedulerType: Scheduler> : Sink<O>, ObserverType {
    typealias Element = O.Element
    typealias ParentType = Throttle<Element, SchedulerType>
    
    let parent: ParentType
    
    var lock = NSRecursiveLock()
    // state
    var id = 0 as UInt64
    let value = RxMutableBox<Element?>(nil)
    
    let cancellable = SerialDisposable()
    
    init(parent: ParentType, observer: O, cancel: Disposable) {
        self.parent = parent
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let subscription = parent.source.subscribeSafe(self)
        
        return CompositeDisposable(subscription, cancellable)
    }

    func on(event: Event<Element>) {
        switch event {
        case .Next:
            break
        case .Error: fallthrough
        case .Completed:
            cancellable.dispose()
            break
        }
       
        let latestId = self.lock.calculateLocked { () -> UInt64 in
            let observer = self.observer
            
            var oldValue = self.value.value
            
            self.id = self.id &+ 1
            
            switch event {
            case .Next(let element):
                self.value.value = element
            case .Error(let error):
                self.value.value = nil
                observer?.on(event)
                self.dispose()
            case .Completed:
                self.value.value = nil
                if let value = oldValue {
                    observer?.on(.Next(value))
                }
                observer?.on(.Completed)
                self.dispose()
            }
            
            return id
        }
        
        
        switch event {
        case .Next(_):
            let d = SingleAssignmentDisposable()
            self.cancellable.disposable = d
            
            let scheduler = self.parent.scheduler
            let dueTime = self.parent.dueTime
            
            let _  = scheduler.scheduleRelative(latestId, dueTime: dueTime) { (id) in
                self.propagate()
                return NopDisposableResult
            }.map { disposeTimer -> Disposable in
                d.disposable = disposeTimer
                return disposeTimer
            }.recoverWith { e -> RxResult<Disposable> in
                self.lock.performLocked {
                    observer?.on(.Error(e))
                    self.dispose()
                }
                return NopDisposableResult
            }
        default: break
        }
    }
    
    func propagate() {
        var originalValue: Element? = self.lock.calculateLocked {
            var originalValue = self.value.value
            self.value.value = nil
            return originalValue
        }
        
        if let value = originalValue {
            observer?.on(.Next(value))
        }
    }
}

class Throttle<Element, SchedulerType: Scheduler> : Producer<Element> {
    
    let source: Observable<Element>
    let dueTime: SchedulerType.TimeInterval
    let scheduler: SchedulerType
    
    init(source: Observable<Element>, dueTime: SchedulerType.TimeInterval, scheduler: SchedulerType) {
        self.source = source
        self.dueTime = dueTime
        self.scheduler = scheduler
    }
    
    override func run<O: ObserverType where O.Element == Element>(observer: O, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = ThrottleSink(parent: self, observer: observer, cancel: cancel)
        setSink(sink)
        return sink.run()
    }
    
}