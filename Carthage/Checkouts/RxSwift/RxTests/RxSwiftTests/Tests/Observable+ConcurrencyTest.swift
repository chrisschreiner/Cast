//
//  Observable+ConcurrencyTest.swift
//  RxTests
//
//  Created by Krunoslav Zaher on 5/2/15.
//
//

import Foundation
import XCTest
import RxSwift
import RxBlocking

class ObservableConcurrencyTestBase : RxTest {
    var lock = OS_SPINLOCK_INIT

    func performLocked(action: () -> Void) {
        OSSpinLockLock(&lock)
        action()
        OSSpinLockUnlock(&lock)
    }

    override func tearDown() {
#if TRACE_RESOURCES
        sleep(0.1) // wait 100 ms for proper scheduler disposal
#endif
        super.tearDown()
    }
}

class ObservableConcurrencyTest : ObservableConcurrencyTestBase {
}

// observeSingleOn
extension ObservableConcurrencyTest {
    func testObserveSingleOn_DeadlockSimple() {
        let scheduler = TestScheduler(initialClock: 0)

        var nEvents = 0

        let observable = just(0).observeSingleOn(scheduler)
        let _d = observable .subscribeNext { n in
                nEvents++
            }
            .scopedDispose

        scheduler.start()

        XCTAssertEqual(nEvents, 1)
    }

    func testObserveSingleOn_DeadlockErrorImmediatelly() {
        let scheduler = TestScheduler(initialClock: 0)

        var nEvents = 0

        let observable: Observable<Int> = failWith(testError).observeSingleOn(scheduler)
        let _d = observable.subscribeError { n in
                nEvents++
            }
            .scopedDispose

        scheduler.start()

        XCTAssertEqual(nEvents, 1)
    }

    func testObserveSingleOn_DeadlockEmpty() {
        let scheduler = TestScheduler(initialClock: 0)

        var nEvents = 0

        let observable: Observable<Int> = empty().observeSingleOn(scheduler)
        let _d = observable .subscribeCompleted {
                nEvents++
            }
            .scopedDispose

        scheduler.start()

        XCTAssertEqual(nEvents, 1)
    }

    func testObserveSingleOn_Never() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
                next(150, 1),
            ])

        let res = scheduler.start { xs.observeSingleOn(scheduler) }

        let correctMessages: [Recorded<Int>] = [
        ]

        let correctSubscriptions = [
            Subscription(200, 1000)
        ]

        XCTAssertEqual(res.messages, correctMessages)
        XCTAssertEqual(xs.subscriptions, correctSubscriptions)
    }

    func testObserveSingleOn_Empty() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
            next(150, 1),
            completed(300)
            ])

        let res = scheduler.start { xs.observeSingleOn(scheduler) }

        let correctMessages: [Recorded<Int>] = [
            completed(301)
        ]

        let correctSubscriptions = [
            Subscription(200, 301)
        ]

        XCTAssertEqual(res.messages, correctMessages)
        XCTAssertEqual(xs.subscriptions, correctSubscriptions)
    }

    func testObserveSingleOn_Simple() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
            next(150, 1),
            next(210, 0),
            completed(300)
            ])

        let res = scheduler.start { xs.observeSingleOn(scheduler) }

        let correctMessages: [Recorded<Int>] = [
            next(301, 0),
            completed(301)
        ]

        let correctSubscriptions = [
            Subscription(200, 301)
        ]

        XCTAssertEqual(res.messages, correctMessages)
        XCTAssertEqual(xs.subscriptions, correctSubscriptions)
    }

    func testObserveSingleOn_Error() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
            next(150, 1),
            error(300, testError)
            ])

        let res = scheduler.start { xs.observeSingleOn(scheduler) }

        let correctMessages: [Recorded<Int>] = [
            error(301, testError)
        ]

        let correctSubscriptions = [
            Subscription(200, 301)
        ]

        XCTAssertEqual(res.messages, correctMessages)
        XCTAssertEqual(xs.subscriptions, correctSubscriptions)
    }

    func testObserveSingleOn_Dispose() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
            next(150, 1),
            next(290, 0),
            error(300, testError)
            ])

        let res = scheduler.start(290) { xs.observeSingleOn(scheduler) }

        let correctMessages: [Recorded<Int>] = [
        ]

        let correctSubscriptions = [
            Subscription(200, 290)
        ]

        XCTAssertEqual(res.messages, correctMessages)
        XCTAssertEqual(xs.subscriptions, correctSubscriptions)
    }
}

// observeOn serial scheduler
extension ObservableConcurrencyTest {

    func runDispatchQueueSchedulerTests(tests: (scheduler: SerialDispatchQueueScheduler) -> Disposable) {
        let scheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "testQueue1")
        let _ = runDispatchQueueSchedulerTests(scheduler, tests: tests).scopedDispose
    }

    func runDispatchQueueSchedulerTests(scheduler: SerialDispatchQueueScheduler, tests: (scheduler: SerialDispatchQueueScheduler) -> Disposable) -> Disposable {
        // simplest possible solution, even though it has horrible efficiency in this case probably
        var wait = OS_SPINLOCK_INIT
        OSSpinLockLock(&wait)

        let disposable = tests(scheduler: scheduler)

        scheduler.schedule(()) { s in
            OSSpinLockUnlock(&wait)
            return NopDisposableResult
        }

        OSSpinLockLock(&wait)

        return disposable
    }

    func runDispatchQueueSchedulerMultiplexedTests(tests: [(scheduler: SerialDispatchQueueScheduler) -> Disposable]) {
        let scheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "testQueue1")

        let compositeDisposable = CompositeDisposable()

        for test in tests {
            compositeDisposable.addDisposable(runDispatchQueueSchedulerTests(scheduler, tests: test))
        }

        compositeDisposable.dispose()
    }

    // tests

    func testObserveOnDispatchQueue_DoesPerformWorkOnQueue() {
        let unitTestsThread = NSThread.currentThread()

        var didExecute = false

        runDispatchQueueSchedulerTests { scheduler in
            let observable = just(0)
                .observeOn(scheduler)
            return observable .subscribeNext { n in
                didExecute = true
                XCTAssert(NSThread.currentThread() !== unitTestsThread)
            }
        }



        XCTAssert(didExecute)
    }

#if TRACE_RESOURCES
    func testObserveOnDispatchQueue_EnsureCorrectImplementationIsChosen() {
        runDispatchQueueSchedulerTests { scheduler in
            XCTAssert(numberOfSerialDispatchQueueObservables == 0)
            let observable = just(0)
                .observeOn(scheduler)
            XCTAssert(numberOfSerialDispatchQueueObservables == 1)
            return NopDisposable.instance
        }

        XCTAssert(numberOfSerialDispatchQueueObservables == 0)
    }

    func testObserveOnDispatchQueue_DispatchQueueSchedulerIsSerial() {
        var numberOfConcurrentEvents: Int32 = 0
        var numberOfExecutions = 0
        runDispatchQueueSchedulerTests { scheduler in
            XCTAssert(numberOfSerialDispatchQueueObservables == 0)
            return sequenceOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
                .observeOn(scheduler)
                .subscribeNext { e in
                    XCTAssert(OSAtomicIncrement32(&numberOfConcurrentEvents) == 1)
                    self.sleep(0.1) // should be enough to block the queue, so if it's concurrent, it will fail
                    XCTAssert(OSAtomicDecrement32(&numberOfConcurrentEvents) == 0)
                    numberOfExecutions++
                }
        }

        XCTAssert(numberOfSerialDispatchQueueObservables == 0)
        XCTAssert(numberOfExecutions == 11)
    }
#endif

    func testObserveOnDispatchQueue_DeadlockErrorImmediatelly() {
        var nEvents = 0

        runDispatchQueueSchedulerTests { scheduler in
            let observable: Observable<Int> = failWith(testError).observeOn(scheduler)
            return observable .subscribeError { n in
                nEvents++
            }
        }

        XCTAssertEqual(nEvents, 1)
    }

    func testObserveOnDispatchQueue_DeadlockEmpty() {
        var nEvents = 0

        runDispatchQueueSchedulerTests { scheduler in
            let observable: Observable<Int> = empty().observeOn(scheduler)
            return observable .subscribeCompleted {
                nEvents++
            }
        }

        XCTAssertEqual(nEvents, 1)
    }

    func testObserveOnDispatchQueue_Never() {
        runDispatchQueueSchedulerTests { scheduler in
            let xs: Observable<Int> = never()
            return xs
                .observeOn(scheduler)
                .subscribeNext { n in
                    XCTAssert(false)
                }
        }
    }

    func testObserveOnDispatchQueue_Simple() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        runDispatchQueueSchedulerMultiplexedTests([
            { scheduler in
                let subscription = (xs.observeOn(scheduler)).subscribe(observer)
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendNext(xs, 0)

                return subscription
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0)
                    ])
                sendNext(xs, 1)
                sendNext(xs, 2)
                return NopDisposable.instance
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0),
                    next(1),
                    next(2)
                    ])
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendCompleted(xs)
                return NopDisposable.instance
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0),
                    next(1),
                    next(2),
                    completed(0)
                    ])
                XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
                return NopDisposable.instance
            },
            ])
    }

    func testObserveOnDispatchQueue_Empty() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        runDispatchQueueSchedulerMultiplexedTests([
            { scheduler in
                let subscription = (xs.observeOn(scheduler)).subscribe(observer)
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendCompleted(xs)
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])

                return subscription
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    completed()
                ])
                XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
                return NopDisposable.instance
            }
        ])
    }

    func testObserveOnDispatchQueue_Error() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        runDispatchQueueSchedulerMultiplexedTests([
            { scheduler in
                let subscription = (xs.observeOn(scheduler)).subscribe(observer)
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendNext(xs, 0)

                return subscription
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0)
                    ])
                sendNext(xs, 1)
                sendNext(xs, 2)
                return NopDisposable.instance
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0),
                    next(1),
                    next(2)
                    ])
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendError(xs, testError)
                return NopDisposable.instance
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0),
                    next(1),
                    next(2),
                    error(testError)
                    ])
                XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
                return NopDisposable.instance
            },
        ])
    }

    func testObserveOnDispatchQueue_Dispose() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()
        var subscription: Disposable!

        runDispatchQueueSchedulerMultiplexedTests([
            { scheduler in
                subscription = (xs.observeOn(scheduler)).subscribe(observer)
                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                sendNext(xs, 0)

                return subscription
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0)
                    ])

                XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
                subscription.dispose()
                XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])

                sendError(xs, testError)

                return NopDisposable.instance
            },
            { scheduler in
                XCTAssertEqual(observer.messages, [
                    next(0),
                    ])
                XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
                return NopDisposable.instance
            }
        ])
    }
}

// observeOn concurrent scheduler
class ObservableConcurrentSchedulerConcurrencyTest: ObservableConcurrencyTestBase {

    func createScheduler() -> ImmediateScheduler {
        let operationQueue = NSOperationQueue()
        operationQueue.maxConcurrentOperationCount = 8
        return OperationQueueScheduler(operationQueue: operationQueue)
    }

#if TRACE_RESOURCES
    func testObserveOn_EnsureCorrectImplementationIsChosen() {
        let scheduler = self.createScheduler()

        XCTAssert(numberOfSerialDispatchQueueObservables == 0)
        let observable = just(0).observeOn(scheduler)
        self.sleep(0.1)
        XCTAssert(numberOfSerialDispatchQueueObservables == 0)
    }
#endif

    func testObserveOn_EnsureTestsAreExecutedWithRealConcurrentScheduler() {
        var variable: Int = 0

        var events: [String] = []

        var stop = BehaviorSubject(value: 0)

        let scheduler = createScheduler()

        let condition = NSCondition()

        var writtenStarted = 0
        var writtenEnded = 0

        var concurrent = { () -> RxResult<Disposable> in
            self.performLocked {
                events.append("Started")
            }

            condition.lock()
            writtenStarted++
            condition.signal()
            while writtenStarted < 2 {
                condition.wait()
            }
            condition.unlock()

            self.performLocked {
                events.append("Ended")
            }

            condition.lock()
            writtenEnded++
            condition.signal()
            while writtenEnded < 2 {
                condition.wait()
            }
            condition.unlock()

            stop.on(.Completed)

            return NopDisposableResult
        }

        _ = scheduler.schedule((), action: concurrent)

        _ = scheduler.schedule((), action: concurrent)

        let _ = stop.last

        XCTAssertEqual(events, ["Started", "Started", "Ended", "Ended"])
    }

    func testObserveOn_Never() {
        let scheduler = createScheduler()

        let xs: Observable<Int> = never()
        let subscription = xs
            .observeOn(scheduler)
            .subscribeNext { n in
                XCTAssert(false)
        }

        sleep(0.1)

        subscription.dispose()
    }

    func testObserveOn_Simple() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        let scheduler = createScheduler()

        let stop = Variable(0)

        let subscription = (xs.observeOn(scheduler)).subscribe(observer)
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendNext(xs, 0)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0)
            ])
        sendNext(xs, 1)
        sendNext(xs, 2)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0),
            next(1),
            next(2)
            ])
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendCompleted(xs)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0),
            next(1),
            next(2),
            completed(0)
            ])
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])

        subscription.dispose()

        sleep(0.1)
    }

    func testObserveOn_Empty() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        let scheduler = createScheduler()

        _ = (xs.observeOn(scheduler)).subscribe(observer)
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendCompleted(xs)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            completed()
            ])
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
    }

    func testObserveOn_ConcurrentSchedulerIsSerialized() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        var executed = false

        let scheduler = createScheduler()

        let res = xs
            .observeOn(scheduler)
            .map { v -> Int in
                if v == 0 {
                    self.sleep(0.1) // 100 ms is enough
                    executed = true
                }
                return v
        }
        let subscription = res.subscribe(observer)

        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendNext(xs, 0)
        sendNext(xs, 1)
        sendCompleted(xs)

        sleep(0.3)

        XCTAssertEqual(observer.messages, [
            next(0, 0),
            next(0, 1),
            completed()
            ])
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])

        XCTAssert(executed)

        subscription.dispose()
    }

    func testObserveOn_Error() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        let scheduler = createScheduler()

        let _ = (xs.observeOn(scheduler)).subscribe(observer)
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendNext(xs, 0)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0)
            ])
        sendNext(xs, 1)
        sendNext(xs, 2)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0),
            next(1),
            next(2)
            ])
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendError(xs, testError)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0),
            next(1),
            next(2),
            error(testError)
            ])
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])

    }

    func testObserveOn_Dispose() {
        let xs = PrimitiveHotObservable<Int>()
        let observer = PrimitiveMockObserver<Int>()

        let scheduler = createScheduler()
        let subscription = (xs.observeOn(scheduler)).subscribe(observer)
        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        sendNext(xs, 0)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0)
            ])

        XCTAssert(xs.subscriptions == [SubscribedToHotObservable])
        subscription.dispose()
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])

        sendError(xs, testError)

        sleep(0.1)

        XCTAssertEqual(observer.messages, [
            next(0),
            ])
        XCTAssert(xs.subscriptions == [UnsunscribedFromHotObservable])
    }
}

class ObservableConcurrentSchedulerConcurrencyTest2 : ObservableConcurrentSchedulerConcurrencyTest {
    override func createScheduler() -> ImmediateScheduler {
        return ConcurrentDispatchQueueScheduler(globalConcurrentQueuePriority: .Default)
    }
}

// subscribeOn

extension ObservableConcurrencyTest {
    func testSubscribeOn_SchedulerSleep() {
        let scheduler = TestScheduler(initialClock: 0)

        var scheduled = 0
        var disposed = 0

        let xs: Observable<Int> = create { observer in
            scheduled = scheduler.clock
            return AnonymousDisposable {
                disposed = scheduler.clock
            }
        }

        let res = scheduler.start {
            xs.subscribeOn(scheduler)
        }

        XCTAssertEqual(res.messages, [

            ])

        XCTAssertEqual(scheduled, 201)
        XCTAssertEqual(disposed, 1001)
    }

    func testSubscribeOn_SchedulerCompleted() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs: HotObservable<Int> = scheduler.createHotObservable([
            completed(300)
            ])

        let res = scheduler.start {
            xs.subscribeOn(scheduler)
        }

        XCTAssertEqual(res.messages, [
            completed(300)
            ])

        XCTAssertEqual(xs.subscriptions, [
            Subscription(201, 301)
            ])
    }

    func testSubscribeOn_SchedulerError() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs: HotObservable<Int> = scheduler.createHotObservable([
            error(300, testError)
            ])

        let res = scheduler.start {
            xs.subscribeOn(scheduler)
        }

        XCTAssertEqual(res.messages, [
            error(300, testError)
            ])

        XCTAssertEqual(xs.subscriptions, [
            Subscription(201, 301)
            ])
    }

    func testSubscribeOn_SchedulerDispose() {
        let scheduler = TestScheduler(initialClock: 0)

        let xs = scheduler.createHotObservable([
            next(150, 1),
            next(210, 2),
            ])

        let res = scheduler.start {
            xs.subscribeOn(scheduler)
        }

        XCTAssertEqual(res.messages, [
            next(210, 2),
            ])

        XCTAssertEqual(xs.subscriptions, [
            Subscription(201, 1001)
            ])
    }
}
