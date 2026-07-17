import ThreadBeaconCore

let threadCountFormatterTests = [
    TestCase(name: "thread count shows running and visible totals") {
        let label = ThreadCountFormatter.label(for: [
            .running,
            .running,
            .running,
            .idle,
            .justCompleted,
            .unknown,
            .needsAction,
            .error,
        ])

        try expect(label.displayText == "3/8", "expected three running tasks among eight visible")
        try expect(
            label.explanation == "3 个任务正在运行，共显示 8 个任务",
            "expected the count meaning in the explanation"
        )
    },
    TestCase(name: "thread count handles an empty list") {
        let label = ThreadCountFormatter.label(for: [])

        try expect(label.displayText == "0/0", "expected an empty task count")
        try expect(
            label.explanation == "0 个任务正在运行，共显示 0 个任务",
            "expected the empty count meaning in the explanation"
        )
    },
]
