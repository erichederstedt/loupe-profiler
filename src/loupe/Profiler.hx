package loupe;

import haxe.Json;
import haxe.macro.Context;
import haxe.macro.Expr;
import thx.Assert;

using thx.Arrays;

#if js
import js.Browser;
import js.html.AnchorElement;
import js.html.Blob;
import js.html.URL;
#else
import haxe.Timer;
import sys.io.File;
#end

/**
	Represents a performance profiling mark
**/
class Mark {
	public final name:String;
	public final parent:Null<Mark>;
	public final children:Array<Mark>;

	public final timestampBegin:Float;
	public var timestampEnd:Float;

	public function new(name:String, timestampBegin:Float, ?parent:Null<Mark>) {
		this.name = name;
		this.parent = parent;
		this.children = [];

		this.timestampBegin = timestampBegin;
		this.timestampEnd = 0.0;

		if (parent != null) {
			parent.children.push(this);
		}
	}
}

/**
	Helper class for Googles TraceEvent json format: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/
**/
@:structInit
class TraceEvent {
	public final name:String;
	public final cat:String;
	public final ph:String;
	public final pid:Int;
	public final tid:Int;
	public final ts:Int;
}

/**
	An instrumentation-based profiler
**/
class Profiler {
	static final _markStack:Array<Mark> = [];
	static final _markRecord:Array<Mark> = [];
	static var _isRecording = false;

	/**
		Starts recording a profile

		@example
		```haxe
		Profiler.startProfiling(); // Profiling is disabled by default, so you must always do this once before starting to call the profiling functions or they won't be recorded.
		```
	**/
	public static function startProfiling() {
		_isRecording = true;
		_markStack.resize(0);
		_markRecord.resize(0);
	}

	/**
		Stops recording a profile

		@example
		```haxe
		Profiler.stopProfiling();
		```
	**/
	public static function stopProfiling() {
		_isRecording = false;
	}

	/**
		Starts a profile block

		@param name The name of the profiled block

		@example
		```haxe
		Profiler.profileBlockStart("block1");
		// Work you want to profile
		Profiler.profileBlockEnd();
		```
	**/
	public static function profileBlockStart(name:String) {
		if (!_isRecording) {
			return;
		}

		_markStack.push(new Mark(name, timestamp(), (_markStack.length != 0) ? _markStack[_markStack.length - 1] : null));
	}

	/**
		Ends a profile block

		@example
		```haxe
		Profiler.profileBlockStart("block1");
		// Work you want to profile
		Profiler.profileBlockEnd();
		```
	**/
	public static function profileBlockEnd() {
		if (!_isRecording) {
			return;
		}

		Assert.isFalse(_markStack.length <= 0, 'There is no mark to pop. The number of profileBlockStart and profileBlockEnd do not match.');

		final mark = _markStack.pop();
		mark.timestampEnd = timestamp();

		_markRecord.pushIf(mark.parent == null, mark);
	}

	/**
		Profiles a code block

		@param mark The mark which will be dumped
		@param expr The code block that will be profiled

		@return The modified AST

		@example
		```haxe
		Profiler.profileBlock("block3", {
			// Work you want to profile
		});
		```
	**/
	macro public static function profileBlock(name:String, expr:Expr):Expr {
		final body = switch expr.expr {
			case EBlock(_):
				expr;
			case _:
				macro {$expr;}
		}

		return macro {
			Profiler.profileBlockStart($v{name});
			try {
				$body;
			} catch (e:Dynamic) {
				Profiler.profileBlockEnd();
				throw e;
			}
			Profiler.profileBlockEnd();
		}
	}

	/**
		Gets a timestamp

		@return The timestamp
	**/
	inline public static function timestamp():Float {
		#if js
		return Browser.window.performance.now();
		#else
		return Timer.stamp() * 1000.0 * 1000.0;
		#end
	}

	/**
		Prints the recorded mark

		@param mark The mark which will be printed
		@param depth The level of indentation which will be printed
	**/
	public static function printMark(mark:Mark, depth = 0) {
		final indent = StringTools.lpad('', '-', depth);
		trace(indent + 'Mark: ' + mark.name + ', Begin: ' + mark.timestampBegin + ', End: ' + mark.timestampEnd);
		mark.children.each(mark -> printMark(mark, depth + 1));
	}

	/**
		Prints the recorded marks
	**/
	public static function printMarks() {
		_markRecord.each(mark -> printMark(mark));
	}

	/**
		Dumps the recorded mark into a TraceEvent array

		@param mark The mark which will be dumped
		@param outTraceEvents The output array
	**/
	public static function dumpMark(mark:Mark, outTraceEvents:Array<TraceEvent>) {
		final pid = 0;
		final tid = 0;
		final cat = 'PERF';

		outTraceEvents.push({
			name: mark.name,
			cat: cat,
			ph: 'B',
			pid: pid,
			tid: tid,
			ts: Std.int(mark.timestampBegin)
		});

		mark.children.each(child -> dumpMark(child, outTraceEvents));

		outTraceEvents.push({
			name: mark.name,
			cat: cat,
			ph: 'E',
			pid: pid,
			tid: tid,
			ts: Std.int(mark.timestampEnd)
		});
	}

	/**
		Dumps the recorded profile to a dynamic object

		@return The dumped recorded profile as a dynamic object
	**/
	public static function dumpToObject():Dynamic {
		final traceEvents:Array<TraceEvent> = [];
		_markRecord.each(mark -> dumpMark(mark, traceEvents));
		return {
			traceEvents: traceEvents,
			displayTimeUnit: 'ms'
		};
	}

	/**
		Dumps the recorded profile to a json string

		@return The dumped recorded profile as a json string

		@example
		```haxe
		Profiler.profileBlockStart("block2");
		// Work you want profile
		Profiler.profileBlockEnd();

		trace(Profiler.dumpToJson());
		```
	**/
	public static function dumpToJson():String {
		return Json.stringify(dumpToObject());
	}

	/**
		Dumps the recorded profile to a json file

		@param filename The filename for the profile, including json extension

		@example
		```haxe
		Profiler.profileBlockStart("block2");
		// Work you want profile
		Profiler.profileBlockEnd();

		Profiler.dumpToJsonFile("profile_dump.json");
		```
	**/
	public static function dumpToJsonFile(filename:String) {
		final jsonString = dumpToJson();
		#if js
		final blob = new Blob([jsonString], {type: 'application/json'});
		final url = URL.createObjectURL(blob);
		final link:AnchorElement = cast Browser.document.createAnchorElement();
		link.href = url;
		link.download = filename;
		Browser.document.body.appendChild(link);
		link.click();
		Browser.document.body.removeChild(link);
		URL.revokeObjectURL(url);
		#else
		File.saveContent(filename, jsonString);
		#end
		trace('Profiler data saved.');
	}

	/**
		Injects the profiler macro into a class, is required for the @:profile macro

		@return Modified class fields

		@example
		```haxe
		@:build(hacksaw.profiler.Profiler.injectProfiler())
		class Foo {
			@:profile
			public function bar() {
				// Work you want to profile
			}
		}
		```
	**/
	macro public static function injectProfiler():Array<Field> {
		final pos = Context.currentPos();
		final fields = Context.getBuildFields();
		final localClass = Context.getLocalClass();
		if (localClass == null) {
			return fields;
		}

		fields.filter(field -> field.meta != null && field.meta.find(m -> m.name == ':profile') != null).each(field -> {
			switch field.kind {
				case FFun(func):
					func.expr = macro {
						Profiler.profileBlockStart($v{'${localClass.get().name}:${field.name}'});
						try {
							${func.expr};
						} catch (e:Dynamic) {
							Profiler.profileBlockEnd();
							throw e;
						}
						Profiler.profileBlockEnd();
					}
					field.kind = FFun(func);
				default:
					Context.error('Cannot mark non-function field as :profile!', Context.currentPos());
			}
		});

		return fields;
	}
}
