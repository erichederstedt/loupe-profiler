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
	var firstProfile:Dynamic = null;
	var secondProfile:Dynamic = null;

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

			final foo = new Foo();
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
			Profiler.stopProfiling();

			firstProfile = Profiler.dumpToObject();
			Profiler.printMarks();

			it("firstProfile should have the displayTimeUnit ms", {
				firstProfile.displayTimeUnit.should.be("ms");
			});
			it("firstProfile should have an even amount of traceEvents", {
				final isTraceEventsEven = (firstProfile.traceEvents.length % 2) == 0;
				isTraceEventsEven.should.be(true); // Number of begin and end traces must match!
			});
			it("firstProfile should have 10 total trace events for this test", {
				firstProfile.traceEvents.length.should.be(10); // This example should only produce 10 traces.
			});
			it("firstProfile should register all traces for this test", {
				final hasBlock1Trace = hasTraceEvent(firstProfile, "block1");
				final hasBlock2Trace = hasTraceEvent(firstProfile, "block2");
				final hasBlock3Trace = hasTraceEvent(firstProfile, "block3");
				final hasFooBarTrace = hasTraceEvent(firstProfile, "Foo:bar");
				final hasBlock2_2Trace = hasTraceEvent(firstProfile, "block2", 1);
				final hasBlock4Trace = hasTraceEvent(firstProfile, "block4");
				hasBlock1Trace.should.be(true);
				hasBlock2Trace.should.be(true);
				hasBlock3Trace.should.be(true);
				hasFooBarTrace.should.be(true);
				hasBlock2_2Trace.should.be(true);
				hasBlock4Trace.should.be(false);
			});

			Profiler.stopProfiling();
			Profiler.startProfiling();
			Profiler.profileBlockStart("block1");
			Sys.sleep(0.1);
			Profiler.profileBlockEnd();
			Profiler.stopProfiling();

			secondProfile = Profiler.dumpToObject();

			it("secondProfile should have 2 total trace events for this test", {
				secondProfile.traceEvents.length.should.be(2); // This example should only produce 2 traces.
			});
		});
	}

	function hasTraceEvent(object:Dynamic, name:String, skip:Int = 0, ph:String = "B"):Bool {
		return object.traceEvents.filter((event) -> event.name == name && event.ph == ph).length > skip;
	}
}
