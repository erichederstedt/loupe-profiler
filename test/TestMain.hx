package;

import buddy.*;
import haxe.Timer;
import loupe.Profiler;
import nanoui.Context;

using buddy.Should;

@:build(loupe.Profiler.injectProfiler())
class Foo {
	@:profile
	public function bar() {
		trace("bar");
	}

	public function new() {}
}

class TestMain extends buddy.SingleSuite {
	var object:Dynamic = null;

	public function new() {
		describe("Testing", {
			Profiler.profileBlockStart("ignoredBlock1");
			Sys.sleep(0.1);
			Profiler.profileBlockEnd();

			Profiler.startProfiling();
			Profiler.profileBlockStart("block1");
			Sys.sleep(0.1);

			Profiler.profileBlockStart("block2");
			Sys.sleep(0.1);

			Profiler.profileBlock("block3", {
				Sys.sleep(0.1);
			});

			Profiler.profileBlockEnd();

			var foo = new Foo();
			foo.bar(); // Profiled through macro

			Sys.sleep(0.1);

			Profiler.profileBlockStart("block2");
			Sys.sleep(0.1);
			Profiler.profileBlockEnd();
			Profiler.profileBlockEnd();

			Profiler.stopProfiling();

			Profiler.profileBlockStart("ignoredBlock2");
			Sys.sleep(0.1);
			Profiler.profileBlockEnd();

			object = Profiler.dumpToObject();
			Profiler.printMarks();

			it("should have the displayTimeUnit ms", {
				object.displayTimeUnit.should.be("ms");
			});
			it("should have an even amount of traceEvents", {
				final isTraceEventsEven = (object.traceEvents.length % 2) == 0;
				isTraceEventsEven.should.be(true); // Number of begin and end traces must match!
			});
			it("should have 10 total trace events for this test", {
				object.traceEvents.length.should.be(10); // This example should only produce 10 traces.
			});
			it("should register all traces for this test", {
				final hasBlock1Trace = hasTraceEvent("block1");
				final hasBlock2Trace = hasTraceEvent("block2");
				final hasBlock3Trace = hasTraceEvent("block3");
				final hasFooBarTrace = hasTraceEvent("Foo:bar");
				final hasBlock2_2Trace = hasTraceEvent("block2", 1);
				hasBlock1Trace.should.be(true);
				hasBlock2Trace.should.be(true);
				hasBlock3Trace.should.be(true);
				hasFooBarTrace.should.be(true);
				hasBlock2_2Trace.should.be(true);
			});
		});
	}

	function hasTraceEvent(name:String, skip:Int = 0, ph:String = "B"):Bool {
		if (object.traceEvents.filter((event) -> event.name == name && event.ph == ph).length > skip)
			return true;
		return false;
	}
}
