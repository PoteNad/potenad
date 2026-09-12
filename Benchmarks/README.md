# Latency measurements

Run the optimized native benchmark with:

    swift build -c release --scratch-path .build-performance -Xswiftc -DPERFORMANCE
    .build-performance/release/PoteNad --benchmark

`before.txt` and `after.txt` are retained measurements from the original v1 interface. They include the old inline Settings and custom Find implementations, which v2 replaced with standard AppKit interfaces. Current benchmark output covers typing, zoom, serialization, and incremental line indexing. Windows are not presented, and measurements exclude WindowServer/display presentation. Small timing differences are noise, not evidence of improvement.
