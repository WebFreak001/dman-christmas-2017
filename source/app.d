import d2d;

import cyclic;
import std.algorithm;
import std.conv;
import std.getopt;
import std.random;

float scale = 4;
int maxFps = 240;

enum minX = 0;
enum minY = 84;
enum maxX = 192;
enum maxY = 130;

bool paused;

struct ActiveObstacle
{
	vec2 pos;
	int image;
}

DMan dman;
Road road;
int score = 0;
int scoreNumber = 0;
__gshared string finalScoreString;

enum aimTimeLength = 12;
enum baseMovement = vec2(0.45, 0);
int frames = 0;

Window window;

pragma(inline, true) double speed()
{
	if (paused || dman.failed && dman.failFrame >= 0.999)
		return 0;
	return pow(cast(double) frames + 2000, 0.41) / 32.0 * (dman.failed ? 1 - dman.failFrame : 1);
}

pragma(inline, true) vec2 movement()
{
	return baseMovement * speed;
}

// [nonActive, active]
RectangleShape[2][] targets;

struct Target
{
	int type;
	vec2 position = vec2(0);
	bool active;
}

struct House
{
	int type;
	float x = maxX;
	float y = 0;
	Target[2] targets = [Target(0, vec2(24, 64), false), Target(1, vec2(56, 40), false)];

	this(int type)
	{
		this.type = type;
		if (type == 3)
			y = -32;
		if (uniform(0, 10) == 0)
		{
			targets[0].active = true;
			targets[1].active = true;
		}
		else if (uniform(0, 2) == 0)
		{
			targets[0].active = true;
			targets[1].active = false;
		}
		else
		{
			targets[0].active = false;
			targets[1].active = true;
		}
	}
}

struct Road
{
	RectangleShape shape;
	RectangleShape[] obstacles;
	RectangleShape[] houseTypes;
	float x = 0;

	CyclicArray!(ActiveObstacle, 64) activeObstacles;
	CyclicArray!(House, 6) houses;

	void reset()
	{
		houses.clear();
		activeObstacles.clear();
		x = 0;
	}

	void spawnRandomHouse()
	{
		houses ~= House(uniform(0, cast(int) houseTypes.length));
	}

	void impact(float x, float y)
	{
		foreach (ref house; houses.byRef)
		{
			foreach (ref obj; house.targets)
			{
				if (!obj.active)
					continue;
				float tx = (obj.position + vec2(house.x, house.y) - vec2(x, y)).length_squared;
				bool hit = tx < 16 * 16;
				if (!hit && obj.type == 0) // door
					hit = (obj.position - vec2(0, 16) + vec2(house.x, house.y) - vec2(x, y)).length_squared
						< 16 * 16;
				if (hit)
				{
					obj.active = false;
					score++;
					float multiplier = 1;
					if (obj.type == 1)
						multiplier = 2;
					int gotScore = cast(int)(maxFps * multiplier);
					scoreNumber += gotScore;
					addScoreParticle(vec2(x, y), gotScore);
				}
			}
		}
	}

	void draw(IRenderTarget target)
	{
		x += movement.x;

		auto offX = x % 32;
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(-offX, 0, 0);
		foreach (i; 0 .. maxX / 32 + 1)
		{
			target.draw(shape);
			matrixStack.top = matrixStack.top * mat4.translation(32, 0, 0);
		}
		matrixStack.pop();

		if (activeObstacles.length >= activeObstacles.capacity)
			activeObstacles.popFront();

		if (!activeObstacles.length || activeObstacles[$ - 1].pos.x < (maxX - 4) && uniform(0, 50) == 0)
			activeObstacles ~= ActiveObstacle(vec2((maxX + 32), uniform(0, 3) == 0
					? uniform(minY + 8, maxY - 8) : dman.y), cast(int) uniform(0, obstacles.length));

		foreach_reverse (ref obstacle; activeObstacles.byRef)
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(obstacle.pos.x, obstacle.pos.y, 0);
			target.draw(obstacles[obstacle.image]);
			matrixStack.pop();
			obstacle.pos.x -= movement.x;
		}

		if (activeObstacles[0].pos.x < -32)
			activeObstacles.popFront();

		if (houses.length)
		{
			if (houses.length >= houses.capacity)
				houses.popFront();
			enum houseMargin = 2;
			if (houses[$ - 1].x + houseTypes[houses[$ - 1].type].size.x <= maxX - houseMargin)
				houses.put(House(uniform(0, cast(int) houseTypes.length)));
			foreach_reverse (ref house; houses.byRef)
			{
				house.x -= movement.x;
				matrixStack.push();
				matrixStack.top = matrixStack.top * mat4.translation(house.x, 0, 0);
				target.draw(houseTypes[house.type]);
				matrixStack.top = matrixStack.top * mat4.translation(0, house.y, 0);
				foreach (obj; house.targets)
				{
					matrixStack.push();
					matrixStack.top = matrixStack.top * mat4.translation(obj.position.x, obj.position.y, 0);
					target.draw(targets[obj.type][obj.active ? 1 : 0]);
					matrixStack.pop();
				}
				matrixStack.pop();
			}
		}
		else
			houses.put(House(uniform(0, cast(int) houseTypes.length)));
	}
}

struct Animation
{
	float seconds;
	double time = 0;

	bool update()
	{
		time += speed;
		if (time > seconds * 240)
		{
			time = 0;
			return true;
		}
		return false;
	}
}

struct DMan
{
	RectangleShape head, arms;
	RectangleShape[6] legs;
	RectangleShape failedLegs, failedArms;
	int legFrame;
	Animation animation = Animation(0.04);
	int skipFrame;

	float x = minX + 32, y = (minY + maxY) / 2;

	double failFrame = 0;
	bool failed;

	void reset()
	{
		failFrame = 0;
		failed = false;
		x = minX + 32;
		y = (minY + maxY) / 2;
		legFrame = 0;
		skipFrame = 0;
	}

	void draw(IRenderTarget target, bool hint = false)
	{
		if (failed)
		{
			if (failFrame < 1)
				failFrame += 1 / 192.0;
		}
		if (animation.update)
		{
			legFrame = (legFrame + 1) % legs.length;
			skipFrame = (skipFrame + 1) % 4;
		}

		auto offX = x % 32;
		if (hint)
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation((x - 24),
					(y - (skipFrame >= 2 ? 1 : 0)), 0) * mat4.scaling(1, -1, 1);
			target.draw(head);
			matrixStack.pop();
		}
		matrixStack.push();
		if (failed)
		{
			immutable double failTime = failFrame;
			immutable double n = failTime * 7.9;
			double bounce = abs(cos(n) / pow((n + 1), 0.9999));
			matrixStack.top = matrixStack.top * mat4.translation((x - 24), (y - 32 - 8 * bounce), 0);
		}
		else
		{
			matrixStack.top = matrixStack.top * mat4.translation((x - 24),
					(y - 40 - (skipFrame >= 2 ? 1 : 0)), 0);
		}
		if (!hint)
			target.draw(head);
		if (failed)
		{
			target.draw(failedArms);
			target.draw(failedLegs);
		}
		else
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(19, 8, 0);
			giftRect.draw(target);
			matrixStack.pop();
			target.draw(arms);
			target.draw(legs[legFrame]);
		}
		matrixStack.pop();
	}

	void move(vec2 l)
	{
		if (l.length_squared == 0 || failed)
			return;
		x = clamp(x + l.x * 0.2, minX, maxX);
		y = clamp(y + l.y * 0.4, minY, maxY);
	}

	bool hitsObstacle(ref Road r)
	{
		vec2 v = vec2(x, y);
		foreach (ref obstacle; r.activeObstacles.byRef)
			if (((v - vec2(0, 1) - obstacle.pos).mul(vec2(0.5, 1))).length_squared < (4) ^^ 2)
				return true;
		return false;
	}
}

vec2 mul(vec2 a, vec2 b)
{
	return vec2(a.x * b.x, a.y * b.y);
}

struct Input
{
	vec2 velocity = vec2(0);
	vec2 aim = vec2(96, 64);
	bool shooting;

	bool w, a, s, d;

	void handleEvent(Event event)
	{
		switch (event.type)
		{
		case Event.Type.KeyPressed:
			if (event.key == SDLK_w)
				w = true;
			else if (event.key == SDLK_a)
				a = true;
			else if (event.key == SDLK_s)
				s = true;
			else if (event.key == SDLK_d)
				d = true;
			velocity = vec2((a * -1) + (d * 1), (w * -1) + (s * 1));
			break;
		case Event.Type.KeyReleased:
			if (event.key == SDLK_w)
				w = false;
			else if (event.key == SDLK_a)
				a = false;
			else if (event.key == SDLK_s)
				s = false;
			else if (event.key == SDLK_d)
				d = false;
			else if (event.key == SDLK_ESCAPE)
				paused = !paused;
			velocity = vec2((a * -1) + (d * 1), (w * -1) + (s * 1));
			break;
		case Event.Type.MouseButtonPressed:
			if (!dman.failed && event.mousebutton == 1)
				shooting = true;
			break;
		case Event.Type.MouseButtonReleased:
			if (event.mousebutton == 1)
				shooting = false;
			if (dman.failed && dman.failFrame >= 0.99)
			{
				float x = event.x / cast(float) window.width * 192;
				float y = event.y / cast(float) window.height * 128;
				if (x >= 24 && x <= 24 + 64 && y >= 96 && y <= 96 + 16)
					clickTweet();
				else if (x >= 104 && x <= 104 + 64 && y >= 96 && y <= 96 + 16)
					clickRetry();
			}
			break;
		case Event.Type.MouseMoved:
			aim = vec2(event.x / cast(float) window.width * 192,
					event.y / cast(float) window.height * 128);
			break;
		default:
			break;
		}
	}
}

struct Gift
{
	vec2 start;
	vec2 goal;
	float origDist;

	float z() const
	{
		float curDist = (start - goal).length;
		float percent = curDist / origDist;
		return -(percent * 2 - 1) ^^ 2 + 1;
	}
}

vec4 uv(double grid = 16, double texPadding = 0.01 / 256.0)(int left, int top, int right, int bottom)
{
	return vec4(left / grid + texPadding, top / grid + texPadding,
			right / grid - texPadding, bottom / grid - texPadding);
}

struct PresentFont
{
	RectangleShape x;
	RectangleShape[10] numbers;
	float offset;

	void loadBig(Texture tex)
	{
		x = RectangleShape.create(tex, vec2(-2, -16), vec2(16, 16), uv(0, 15, 1, 16));
		foreach (i, ref number; numbers)
			number = RectangleShape.create(tex, vec2(-2, -16), vec2(16, 16),
					uv(0, 5 + cast(int) i, 1, 6 + cast(int) i));
		offset = 12;
	}

	void loadSmall(Texture tex)
	{
		x = RectangleShape.create(tex, vec2(0, -6), vec2(6, 6), uv!(32, 1 / 256.0)(15, 10, 16, 11));
		foreach (i, ref number; numbers)
			number = RectangleShape.create(tex, vec2(0, -10), vec2(6, 14), uv!(32,
					1 / 256.0)(8 + cast(int) i, 8, 9 + cast(int) i, 10));
		offset = 5;
	}

	void draw(IRenderTarget target, string text)
	{
		matrixStack.push();
		foreach (c; text)
		{
			if (c == 'x' || c == '+')
				x.draw(target);
			else if (c >= '0' && c <= '9')
				numbers[c - '0'].draw(target);
			matrixStack.top = matrixStack.top * mat4.translation(offset, 0, 0);
		}
		matrixStack.pop();
	}

	void drawScore(IRenderTarget target, int score)
	{
		matrixStack.push();
		x.draw(target);
		matrixStack.top = matrixStack.top * mat4.translation(offset * ceil(log10(score + 1) + 1), 0, 0);
		if (!score)
			numbers[0].draw(target);
		while (score)
		{
			matrixStack.top = matrixStack.top * mat4.translation(-offset, 0, 0);
			numbers[score % 10].draw(target);
			score /= 10;
		}
		matrixStack.pop();
	}
}

PresentFont presentFont, particleFont;

struct ParticleInfo
{
	vec2 pos;
	int text;
	int frames;
}

CyclicArray!(ParticleInfo, 16) scoreParticles;

void addScoreParticle(vec2 pos, int num)
{
	if (scoreParticles.length >= scoreParticles.capacity)
		scoreParticles.popFront;
	scoreParticles.put(ParticleInfo(pos, num, 0));
}

RectangleShape giftRect;

RectangleShape gameOverText;
RectangleShape scoreText;
RectangleShape tweetButton;
RectangleShape retryButton;

void clickRetry()
{
	score = 0;
	frames = 0;
	scoreParticles.clear();
	dman.reset();
	road.reset();
}

void clickTweet()
{
	import core.thread;
	import std.process : browse;
	import std.uri : encodeComponent;

	new Thread({
		browse("https://twitter.com/intent/tweet?hashtags=DManSanta&text=" ~ (
			"I just scored " ~ finalScoreString ~ " points in DMan Santa! https://santa.wfr.moe")
			.encodeComponent);
	}).start();
}

void main(string[] args)
{
	bool fullscreen, blurry;
	auto info = args.getopt("scale|s", &scale, "fullscreen|f", &fullscreen,
			"blurry|b", &blurry, "speed|r", &maxFps);
	if (info.helpWanted)
	{
		defaultGetoptPrinter("dman-santa-san", info.options);
		return;
	}

	WindowFlags flags = WindowFlags.Default;
	TextureFilterMode filter = blurry ? TextureFilterMode.Linear : TextureFilterMode.Nearest;

	if (fullscreen)
		flags |= WindowFlags.FullscreenAuto;

	window = new Window(cast(int)(maxX * scale), cast(int)(128 * scale),
			"D言語くんサンタさん", flags, DynLibs.image);

	auto fps = new FPSLimiter(maxFps);

	auto tex = new Texture("textures.png", filter, filter);

	presentFont.loadBig(tex);
	particleFont.loadSmall(tex);

	road = Road(RectangleShape.create(tex, vec2(0, 64), vec2(32, 64), uv(7, 0, 9, 4)));

	targets = [[RectangleShape.create(tex, vec2(-8, -32), vec2(16, 48), uv(14, 3, 15, 6)),
		RectangleShape.create(tex, vec2(-8, -32), vec2(32, 48), uv(14, 0, 16, 3))],
		[RectangleShape.create(tex, vec2(-8, -8), vec2(16, 16), uv(14, 6, 15, 7)),
		RectangleShape.create(tex, vec2(-8, -8), vec2(16, 16), uv(15, 6, 16, 7))]];

	road.houseTypes = [RectangleShape.create(tex, vec2(0, 0), vec2(5 * 16, 64), uv(9, 0, 14, 4)),
		RectangleShape.create(tex, vec2(0, 0), vec2(5 * 16, 64), uv(9, 4, 14, 8)),
		RectangleShape.create(tex, vec2(0, 0), vec2(5 * 16, 64), uv(9, 8, 14, 12)),
		RectangleShape.create(tex, vec2(0, 0), vec2(5 * 16, 64), uv(9, 12, 14, 16))];

	road.obstacles = [RectangleShape.create(tex, vec2(-24, -8), vec2(32, 16), uv(5, 1, 7, 2)),
		RectangleShape.create(tex, vec2(-8, -8), vec2(16, 16), uv(6, 2, 7, 3))];

	dman.head = RectangleShape.create(tex, vec2(0, 0), vec2(32, 32), uv(0, 0, 2, 2));
	dman.arms = RectangleShape.create(tex, vec2(0, 0), vec2(48, 32), uv(2, 0, 5, 2));
	foreach (i; 0 .. dman.legs.length)
	{
		dman.legs[i] = RectangleShape.create(tex, vec2(16, 31), vec2(16, 16),
				uv(cast(int) i, 2, cast(int) i + 1, 3));
	}
	dman.failedLegs = RectangleShape.create(tex, vec2(16, 31), vec2(32, 16), uv(5, 3, 7, 4));
	dman.failedArms = RectangleShape.create(tex, vec2(0, 16), vec2(48, 16), uv(1, 4, 4, 5));

	gameOverText = RectangleShape.create(tex, vec2(-56, -32), vec2(112, 16), uv(1, 5, 8, 6));
	scoreText = RectangleShape.create(tex, vec2(-64, -8), vec2(64, 16), uv(1, 6, 5, 7));
	tweetButton = RectangleShape.create(tex, vec2(0, 0), vec2(64, 16), uv(1, 7, 5, 8));
	retryButton = RectangleShape.create(tex, vec2(0, 0), vec2(64, 16), uv(5, 7, 9, 8));

	giftRect = RectangleShape.create(tex, vec2(-8, -16), vec2(16, 16), uv(5, 0, 6, 1));

	int aimTime;
	RectangleShape[5] aimHelper;
	foreach (i; 0 .. 5)
		aimHelper[i] = RectangleShape.create(tex, vec2(-8, -8), vec2(16, 16), uv(i, 3, i + 1, 4));

	CyclicArray!(Gift, 8) gifts;

	Input input;

	matrixStack.top = mat4.scaling(scale, scale, 1);

	Event event; // Or WindowEvent
	while (window.open)
	{
		while (window.pollEvent(event))
		{
			input.handleEvent(event);
			if (event.type == Event.Type.Quit)
				window.close();
		}
		window.clear(0x43 / cast(float) 0xFF, 0xa4 / cast(float) 0xFF, 0x2e / cast(float) 0xFF);

		if (!paused)
			frames++;

		if (!paused && !dman.failed && frames % maxFps == 0)
			scoreNumber++;

		if (!paused)
			dman.move(input.velocity);

		int aimFrame;
		if (!dman.failed && !paused)
		{
			if (input.shooting)
			{
				aimTime++;
				aimFrame = aimTime / aimTimeLength;
				if (aimFrame >= aimHelper.length)
					aimFrame = aimHelper.length - 1;
			}
			else
			{
				if (aimTime > aimHelper.length * aimTimeLength - aimTimeLength / 2)
				{
					auto end = vec2(dman.x, dman.y - 40);
					float d = (end - input.aim).length;
					if (d > 1)
						gifts ~= Gift(end, input.aim, d);
				}
				aimTime = aimTimeLength;
			}
		}

		if (dman.hitsObstacle(road))
		{
			dman.failed = true;
			finalScoreString = scoreNumber.to!string;
		}

		road.draw(window);

		if (scoreParticles.length)
		{
			if (scoreParticles[0].frames > 32)
				scoreParticles.popFront;
			foreach (ref particle; scoreParticles.byRef)
			{
				particle.pos.x -= movement.x;
				matrixStack.push();
				matrixStack.top = matrixStack.top * mat4.translation(particle.pos.x - 10,
						particle.pos.y - particle.frames * 0.1f, 0);
				particleFont.drawScore(window, particle.text);
				matrixStack.pop();
				particle.frames++;
			}
		}

		dman.draw(window);

		size_t i = gifts.length - 1;
		foreach_reverse (ref gift; gifts.byRef)
		{
			scope (exit)
				i--;
			if (!paused)
			{
				gift.start -= movement;
				gift.goal -= movement;
				if ((gift.start - gift.goal).length_squared <= 1)
				{
					road.impact(gift.goal.x, gift.goal.y);
					gifts[i] = gifts[$ - 1];
					gifts.popBack();
					continue;
				}
				vec2 dir = gift.goal - gift.start;
				auto lenSq = dir.length_squared;
				enum giftSpeed = 0.8f;
				if (lenSq > giftSpeed * giftSpeed)
					dir = dir / sqrt(lenSq) * giftSpeed;
				gift.start += dir;
			}
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(gift.start.x,
					gift.start.y - gift.z * gift.origDist * 0.2, 0);
			giftRect.draw(window);
			matrixStack.pop();
		}

		if (!dman.failed && !paused)
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(input.aim.x, input.aim.y, 0);
			aimHelper[aimFrame].draw(window);
			matrixStack.pop();
		}

		drawUI(window);

		window.display();

		fps.wait();
	}
}

void drawUI(IRenderTarget target)
{
	if (!dman.failed)
	{
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(2, 18, 0);
		presentFont.drawScore(target, score);
		matrixStack.pop();
	}

	if (dman.failed && dman.failFrame > 0.9)
	{
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(192 / 2, 128 / 2 + 8, 0);
		gameOverText.draw(window);
		scoreText.draw(window);
		matrixStack.top = matrixStack.top * mat4.translation(0, 8, 0);
		presentFont.draw(window, finalScoreString);
		matrixStack.pop();
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(24, 96, 0);
		tweetButton.draw(window);
		matrixStack.pop();
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(104, 96, 0);
		retryButton.draw(window);
		matrixStack.pop();
	}
}
