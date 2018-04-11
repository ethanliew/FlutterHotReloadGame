import 'package:flutter/material.dart';
import "dart:ui" as ui;
import "package:nima/nima_flutter.dart";
import "package:nima/animation/actor_animation.dart";
import "package:nima/actor_node.dart";
import "package:flutter/scheduler.dart";
import "package:AABB/AABB.dart";
import "dart:math";

enum TerminalSceneState
{
	All,
	Happy,
	Upset,
	Angry
}

class TerminalScene extends LeafRenderObjectWidget
{
	final DateTime startTime;
	final DateTime endTime;
	final TerminalSceneState state;
	final int characterIndex;
	final String message;
	TerminalScene({Key key, this.state, this.characterIndex, this.message, this.startTime, this.endTime}): super(key: key);

	@override
	RenderObject createRenderObject(BuildContext context) 
	{
		return new TerminalSceneRenderer(state, characterIndex, message, startTime, endTime);
	}

	@override
	void updateRenderObject(BuildContext context, covariant TerminalSceneRenderer renderObject)
	{
		renderObject..state = state
					..characterIndex = characterIndex
					..message = message
					..startTime = startTime
					..endTime = endTime;
	}
}

const double MixSpeed = 5.0;

class StateMix
{
	TerminalSceneState state;
	ActorAnimation animation;
	double animationTime;
	double mix;
}

class TerminalCharacter
{
	FlutterActor actor;
	AABB _bounds;
	ActorNode mount;
	List<StateMix> states = new List<StateMix>();
	TerminalSceneState state = TerminalSceneState.All;
	TerminalSceneRenderer scene;
	TerminalCharacter(this.scene, String filename)
	{
		states.add(new StateMix()
									..state = TerminalSceneState.Happy
									..mix = 1.0
									..animationTime = 0.0);

		states.add(new StateMix()
									..state = TerminalSceneState.Upset
									..mix = 0.0
									..animationTime = 0.0);

		states.add(new StateMix()
									..state = TerminalSceneState.Angry
									..mix = 0.0
									..animationTime = 0.0);

		load(filename);
	}

	AABB get bounds
	{
		return _bounds;
	}

	bool recomputeBounds()
	{
		if(_bounds != null) // only do this if bounds has already been computed
		{
			_bounds = actor.computeAABB();
			return true;
		}
		return false;
	}

	ActorAnimation getAnimation(TerminalSceneState state)
	{
		String animationName;
		switch(state)
		{
			case TerminalSceneState.All:
			case TerminalSceneState.Happy:
				animationName = "Happy";
				break;
			case TerminalSceneState.Angry:
				animationName = "Angry";
				break;
			case TerminalSceneState.Upset:
				animationName = "Upset";
				break;
		}
		return actor.getAnimation(animationName);
	}

	void load(String filename)
	{
		actor = new FlutterActor();
		actor.loadFromBundle(filename).then((bool ok)
		{
			for(StateMix sm in states)
			{
				sm.animation = getAnimation(sm.state);
				if(sm.animation != null && sm.state == TerminalSceneState.Happy)
				{
					sm.animationTime = 0.0;
					sm.animation.apply(sm.animationTime, actor, 1.0);
				}
			}
			actor.advance(0.0);
			_bounds = actor.computeAABB();
			this.scene.characterLoaded(this);
		});
	}
	
	void advance(double elapsed, bool animate)
	{
		if(_bounds == null)
		{
			return;
		}

		TerminalSceneState renderState = state;
		if(state == TerminalSceneState.All)
		{
			renderState = TerminalSceneState.Happy;
		}
		for(StateMix sm in states)
		{
			if(sm.state != renderState)
			{
				sm.mix -= elapsed*MixSpeed;
			}
			else
			{
				sm.mix += elapsed*MixSpeed;
			}
			sm.mix = sm.mix.clamp(0.0, 1.0);

			if(sm.mix != 0 && animate)
			{ 
				sm.animationTime = (sm.animationTime+elapsed) % sm.animation.duration;
				sm.animation.apply(sm.animationTime, actor, sm.mix);
			}
		}

		if(mount != null)
		{
			actor.root.x = mount.x;
			actor.root.y = mount.y;
			actor.root.scaleX = mount.scaleX*0.5;
			actor.root.scaleY = mount.scaleY*0.5;
		}
		actor.advance(elapsed);
	}

	void draw(Canvas canvas)
	{
		if(_bounds == null)
		{
			return;
		}
		actor.draw(canvas);
	}
}
const double MessagePadding = 40.0;
const double BubblePaddingH = 20.0;
const double BubblePaddingV = 12.0;

class TerminalSceneRenderer extends RenderBox
{
	FlutterActor _scene;
	ActorAnimation _animation;
	int _characterIndex = 0;
	double _animationTime = 0.0;
	double _lastFrameTime = 0.0;
	Offset _position = new Offset(0.0, 0.0);
	double _contentHeight = 1.0;
	TerminalSceneState _state;
	AABB _bounds;
	AABB _characterBounds;
	String _message;
	ui.Paragraph _messageParagraph;
	DateTime _startTime;
	DateTime _endTime;

	List<TerminalCharacter> _characters = new List<TerminalCharacter>(4);
	List<TerminalCharacter> _renderCharacters = new List<TerminalCharacter>(4);
	
	TerminalSceneRenderer(TerminalSceneState state, int characterIndex, String message, DateTime startTime, DateTime endTime)
	{
		this.state = state;
		this.characterIndex = characterIndex;
		this.message = message;
		this.startTime = startTime;
		this.endTime = endTime;
		
		SchedulerBinding.instance.scheduleFrameCallback(beginFrame);

		List<int> characterNameLookup = <int>[2,1,3,4];
		for(int i = 0; i < 4; i++)
		{
			int ci = characterNameLookup[i];
			_characters[i] = new TerminalCharacter(this, "assets/nima/NPC$ci/NPC$ci");
			_renderCharacters[i] = _characters[i];
		}						

		_scene = new FlutterActor();
		_scene.loadFromBundle("assets/nima/NPCScene/NPCScene").then((bool ok)
		{
			_scene.advance(0.0);
			_bounds = _scene.computeAABB();
			for(int i = 0; i < 4; i++)
			{
				_characters[i].mount = _scene.getNode("NPC${i+1}");
				_characters[i].advance(0.0, true);
			}	
			AABB bounds = _bounds;
			double height = bounds[3] - bounds[1];
			double width = bounds[2] - bounds[0];
			double x = -bounds[0] - width/2.0;
			double y =  -bounds[1] - height/2.0;
			
			_contentHeight = height;
			_position = new Offset(x, y);
			markNeedsLayout();
		});
	}

	DateTime get startTime
	{
		return _startTime;
	}

	set startTime(DateTime value)
	{
		if(_startTime == value)
		{
			return;
		}
		_startTime = value;
	}

	DateTime get endTime
	{
		return _endTime;
	}

	set endTime(DateTime value)
	{
		if(_endTime == value)
		{
			return;
		}
		_endTime = value;
	}

	int get characterIndex
	{
		return _characterIndex;
	}

	set characterIndex(int index)
	{
		if(index == _characterIndex)
		{
			return;
		}
		_characterIndex = index;
		_bubbleOffset = null;
		if(_characters[_characterIndex] != null)
		{
			if(_characters[_characterIndex].recomputeBounds())
			{
				_characterBounds = _characters[_characterIndex].bounds;
			}
			_animation = _scene.getAnimation("Focus${_characterIndex+1}");
		}
		
		markNeedsPaint();
		markNeedsLayout();
	}

	String get message
	{
		return _message;
	}

	set message(String value)
	{
		if(_message == value)
		{
			return;
		}
		_message = value;
		if(_message == null)
		{
			_messageParagraph = null;
			return;	
		}
		
		if(_characters[_characterIndex] != null)
		{
			if(_characters[_characterIndex].recomputeBounds())
			{
				_characterBounds = _characters[_characterIndex].bounds;
			}
		}
		String valueLabel = _message.toUpperCase();
		ui.ParagraphBuilder builder = new ui.ParagraphBuilder(new ui.ParagraphStyle(
			textAlign:TextAlign.start,
			fontFamily: "Inconsolata",
			fontSize: 30.0,
			lineHeight: 30.0
		))..pushStyle(new ui.TextStyle(color:const Color.fromARGB(255, 0, 92, 103)));
		builder.addText(valueLabel);
		_messageParagraph = builder.build();

		markNeedsLayout();
		markNeedsPaint();
	}

	TerminalSceneState get state
	{
		return _state;
	}

	set state(TerminalSceneState state)
	{
		if(_state == state)
		{
			return;
		}
		_state = state;
		if(_characters[_characterIndex] != null)
		{
			if(_characters[_characterIndex].recomputeBounds())
			{
				_characterBounds = _characters[_characterIndex].bounds;
			}
		}

		markNeedsPaint();
		markNeedsLayout();
	}

	Offset get position
	{
		return _position;
	}

	set position(Offset offset)
	{
		if(_position == offset)
		{
			return;
		}
		_position = offset;
	}

	void beginFrame(Duration timeStamp) 
	{
		final double t = timeStamp.inMicroseconds / Duration.microsecondsPerMillisecond / 1000.0;
		
		if(_lastFrameTime == 0 || _bounds == null)
		{
			_lastFrameTime = t;
			SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
			// hack to circumvent not being enable to initialize lastFrameTime to a starting timeStamp (maybe it's just the date?)
			// Is the FrameCallback supposed to pass elapsed time since last frame? timeStamp seems to behave more like a date
			return;
		}

		double elapsed = t - _lastFrameTime;
		_lastFrameTime = t;

		
		TerminalCharacter boss = _characters[_characterIndex];
		bool showOnlyBoss = _animation != null && _animationTime == _animation.duration;
		
		//boss.recomputeBounds();
		bool focusBoss = _state != TerminalSceneState.All;
		
		if(_animation != null)
		{
			if(focusBoss)
			{
				_animationTime += elapsed;
			}
			else
			{
				_animationTime -= elapsed;
			}
			_animationTime = _animationTime.clamp(0.0, _animation.duration);
			_animation.apply(_animationTime, _scene, 1.0);
		}
		_scene.advance(elapsed);


		DateTime now = new DateTime.now();
		double f = 1.0-(now.difference(_startTime).inMilliseconds/_endTime.difference(_startTime).inMilliseconds).clamp(0.0, 1.0);
		if(showOnlyBoss)
		{
			boss.state = f < 0.25 ? TerminalSceneState.Angry : f < 0.6 ? TerminalSceneState.Upset : TerminalSceneState.Happy;
		}
		else
		{
			boss.state = TerminalSceneState.All;
		}
		for(TerminalCharacter character in _characters)
		{
			character.advance(elapsed, !showOnlyBoss || character == boss);
		}

		AABB bounds = focusBoss ? (_characterBounds ?? _bounds) : _bounds;
		const double PadTop = 0.35;
		const double PadBottom = 0.1;
		if(focusBoss)
		{
			bounds = new AABB.clone(bounds);
			double realHeight = bounds[3] - bounds[1];
			bounds[3] += realHeight * PadTop;
			bounds[1] -= realHeight * PadBottom;
			bounds[1] = max(bounds[1], _bounds[1]);
		}
		double height = bounds[3] - bounds[1];
		double width = bounds[2] - bounds[0];
		double x = -bounds[0] - width/2.0;
		double y =  -bounds[1] - height/2.0;
		
		//print("H ${size.height} $height");
		double mix = min(1.0, elapsed*MixSpeed);
		_contentHeight += (height-_contentHeight) * mix;
		_position += new Offset((x-_position.dx)*mix, (y-_position.dy)*mix);

		markNeedsPaint();
		
		SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
	}

	@override
	bool get sizedByParent => true;
	
	@override
	bool hitTestSelf(Offset screenOffset) => true;

	@override
	void performResize() 
	{
		size = constraints.biggest;
	}

	@override
	void performLayout() 
	{
		super.performLayout();

		if(_messageParagraph != null)
		{
			TerminalCharacter talkCharacter = _characters[_state == TerminalSceneState.All ? 0 : _characterIndex];
			if(talkCharacter == null || talkCharacter.bounds == null)
			{
				return;
			}
			AABB b = talkCharacter.bounds;
			_messageParagraph.layout(new ui.ParagraphConstraints(width:  min(300.0, min(size.width-MessagePadding*2.0-BubblePaddingH*2.0, b[2] - b[0] + BubblePaddingH*2))));
		}
	}

	void characterLoaded(TerminalCharacter c)
	{
		TerminalCharacter talkCharacter = _characters[_state == TerminalSceneState.All ? 0 : _characterIndex];
		if(talkCharacter == c && c.recomputeBounds())
		{
			_characterBounds = c.bounds;
		}
		markNeedsLayout();
	}

	Offset _bubbleOffset;

	@override
	void paint(PaintingContext context, Offset offset)
	{
		final Canvas canvas = context.canvas;
		if(_bounds == null)
		{
			return;
		}
		double scale = size.height/_contentHeight;

		canvas.save();		
		canvas.clipRect(offset & size);
		canvas.translate(offset.dx + size.width/2.0, offset.dy + size.height/2.0);
		canvas.scale(scale, -scale);
		canvas.translate(_position.dx, _position.dy);
		_scene.draw(canvas);
		canvas.restore();
		double fadeHeight = size.height*0.75;

		double fadeOpacity = _animation == null ? 0.0 : (_animationTime/_animation.duration);

		canvas.drawRect(new Offset(offset.dx, offset.dy) & new Size(size.width, fadeHeight), 
								new ui.Paint()	..shader = new ui.Gradient.linear(new Offset(0.0, offset.dy + (size.height-fadeHeight)), new Offset(0.0, offset.dy + fadeHeight), <Color>[new Color.fromARGB((100*fadeOpacity).round(), 0, 0, 0), const Color.fromARGB(0, 0, 0, 0)])
											..style = ui.PaintingStyle.fill);

		_renderCharacters.sort((TerminalCharacter a, TerminalCharacter b)
		{
			return ((b.actor.root.y - a.actor.root.y) * 100.0).round();
		});

		TerminalCharacter boss = _characters[_characterIndex];
		bool showOnlyBoss = _animation != null && _animationTime == _animation.duration;
		
		for(TerminalCharacter character in _renderCharacters)
		{
			if(showOnlyBoss && character != boss)
			{
				continue;
			}
			
			canvas.save();		
			if(boss != character)
			{
				canvas.clipRect(offset & size);
			}
			canvas.translate(offset.dx + size.width/2.0, offset.dy + size.height/2.0);
			canvas.scale(scale, -scale);
			canvas.translate(_position.dx, _position.dy);

			character.draw(canvas);
			canvas.restore();
		}
		

		canvas.save();
		if(_messageParagraph != null)
		{
			TerminalCharacter talkCharacter = _characters[_state == TerminalSceneState.All ? 0 : _characterIndex];
			if(talkCharacter != null)
			{
				talkCharacter.recomputeBounds();
			}
			
			canvas.translate(offset.dx + size.width/2.0, offset.dy + size.height/2.0);
			canvas.translate(_position.dx*scale, -_position.dy*scale);
			AABB talkBounds = talkCharacter.bounds;
			
			Offset p = new Offset((talkBounds[0]+talkBounds[2])*0.5*scale-_messageParagraph.width/2.0, -talkBounds[3]*scale - _messageParagraph.height - BubblePaddingV*4.0);
			if(_bubbleOffset == null)
			{
				_bubbleOffset = p;
			}
			_bubbleOffset += new Offset((p.dx-_bubbleOffset.dx)*0.05, (p.dy-_bubbleOffset.dy)*0.2);

			Size bubbleSize = new Size(_messageParagraph.width + BubblePaddingH*2.0, _messageParagraph.height + BubblePaddingV*2.0);
			
			Path bubble = makeBubblePath(bubbleSize.width, bubbleSize.height);
			canvas.translate(_bubbleOffset.dx + 4.0, _bubbleOffset.dy + 7.0);
			canvas.drawPath(bubble, new Paint()..color = const Color.fromARGB(48, 0, 19, 28));
			canvas.translate(-5.0, -10.0);
			canvas.drawPath(bubble, new Paint()..color = Colors.white);
			canvas.drawPath(bubble, new Paint()..color = const Color.fromARGB(255, 0, 92, 103)
													..style = PaintingStyle.stroke
													..strokeWidth = 2.0);

			canvas.drawParagraph(_messageParagraph, new Offset(BubblePaddingH, BubblePaddingV));// new Offset(talkBounds[0]*scale, talkBounds[1]*-scale));
		}
		canvas.restore();
	}

	Path makeBubblePath(double width, double height)
	{
		const double arrowSize = 30.0;
		final double arrowX = width * 0.25;
		const double cornerRadius = 5.0;
		
		const double circularConstant = 0.55;
		const double icircularConstant = 1.0 - circularConstant;

		Path path = new Path();

		path.moveTo(cornerRadius, 0.0);
		path.lineTo(width-cornerRadius, 0.0);
		path.cubicTo(
						width-cornerRadius+cornerRadius*circularConstant, 0.0, 
						width, cornerRadius*icircularConstant,
						width, cornerRadius);
		path.lineTo(width, height - cornerRadius);
		path.cubicTo(
						width, height - cornerRadius + cornerRadius * circularConstant,
						width - cornerRadius * icircularConstant, height,
						width - cornerRadius, height);
		path.lineTo(arrowX+arrowSize, height);
		path.lineTo(arrowX+arrowSize/2.0, height+arrowSize/2.0);
		path.lineTo(arrowX, height);
		path.lineTo(cornerRadius, height);
		path.cubicTo(
						cornerRadius * icircularConstant, height,
						0.0, height - cornerRadius * icircularConstant,
						0.0, height - cornerRadius);
		path.lineTo(0.0, cornerRadius);

		path.cubicTo(
						0.0, cornerRadius * icircularConstant,
						cornerRadius * icircularConstant, 0.0,
						cornerRadius, 0.0);

		path.close();

		
		return path;
	}
}