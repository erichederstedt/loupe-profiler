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

	public function new(name:String, timestampBegin:Float, parent:Null<Mark> = null) {
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
	public var name:String;
	public var cat:String;
	public var ph:String;
	public var pid:Int;
	public var tid:Int;
	public var ts:Int;
}

/**
	An instrumentation-based profiler. Go to the README for usage examples
**/
class Profiler {
	static var _markStack:Array<Mark> = [];
	static var _markRecord:Array<Mark> = [];
	static var _isRecording = false;

	/**
		Starts recording a profile
	**/
	public static function startProfiling() {
		_isRecording = true;
		_markStack = [];
		_markRecord = [];
	}

	/**
		Stops recording a profile
	**/
	public static function stopProfiling() {
		_isRecording = false;
	}

	/**
		Starts a profile block
	**/
	public static function profileBlockStart(name:String) {
		if (!_isRecording) {
			return;
		}

		_markStack.push(new Mark(name, timestamp(), (_markStack.length != 0) ? _markStack[_markStack.length - 1] : null));
	}

	/**
		Ends a profile block
	**/
	public static function profileBlockEnd() {
		if (!_isRecording) {
			return;
		}

		Assert.isFalse(_markStack.length <= 0, 'There is no mark to pop. The number of profileBlockStart and profileBlockEnd do not match.');

		var mark = _markStack.pop();
		mark.timestampEnd = timestamp();

		if (mark.parent == null) {
			_markRecord.push(mark);
		}
	}

	/**
		Profiles a code block

		@param mark The mark which will be dumped
		@param outTraceEvents The output array
	**/
	macro public static function profileBlock(name:String, expr:Expr):Expr {
		var body = switch expr.expr {
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
	public static function printMark(mark:Mark, depth:Int = 0) {
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
	**/
	public static function dumpToObject():Dynamic {
		var traceEvents:Array<TraceEvent> = [];
		_markRecord.each(mark -> dumpMark(mark, traceEvents));
		return {
			traceEvents: traceEvents,
			displayTimeUnit: 'ms'
		};
	}

	/**
		Dumps the recorded profile to a json string
	**/
	public static function dumpToJson():String {
		return Json.stringify(dumpToObject());
	}

	/**
		Dumps the recorded profile to a json file

		@param filename The filename for the profile, including json extension
	**/
	public static function dumpToJsonFile(filename:String) {
		var jsonString = dumpToJson();
		#if js
		var blob = new Blob([jsonString], {type: 'application/json'});
		var url = URL.createObjectURL(blob);
		var link:AnchorElement = cast Browser.document.createAnchorElement();
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
	**/
	macro public static function injectProfiler():Array<Field> {
		var pos = Context.currentPos();
		var fields = Context.getBuildFields();
		var localClass = Context.getLocalClass();
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
