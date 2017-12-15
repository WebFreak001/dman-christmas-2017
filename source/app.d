import d2d;

import std.algorithm;
import std.random;
import cyclic;

enum float scale = 2;

enum minX = 0;
enum minY = 84;
enum maxX = 192;
enum maxY = 130;

struct ActiveObstacle
{
	vec2 pos;
	int image;
}

DMan dman;
int score = 0;

enum aimTimeLength = 16;
enum baseMovement = vec2(0.45, 0);
int frames = 0;

pragma(inline, true) double speed()
{
	return sqrt(cast(double) frames) / 24.0;
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

	ActiveObstacle[] activeObstacles;
	CyclicArray!(House, 6) houses;

	void spawnRandomHouse()
	{
		houses ~= House(uniform(0, cast(int) houseTypes.length));
	}

	void impact(float x, float y)
	{
		foreach (ref house; houses.byRef)
		{
			foreach (obj; house.targets)
			{
				if (!obj.active)
					continue;
				float tx = (obj.position + vec2(house.x, house.y) - vec2(x, y)).length_squared;
				if (tx < 12 * 12)
				{
					obj.active = true;
					score++;
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

		if (!activeObstacles.length || activeObstacles[$ - 1].pos.x < (maxX - 4) && uniform(0, 50) == 0)
			activeObstacles ~= ActiveObstacle(vec2((maxX + 32), uniform(0, 3) == 0
					? uniform(minY + 8, maxY - 8) : dman.y), cast(int) uniform(0, obstacles.length));

		foreach_reverse (i, ref obstacle; activeObstacles)
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(obstacle.pos.x, obstacle.pos.y, 0);
			target.draw(obstacles[obstacle.image]);
			matrixStack.pop();
			obstacle.pos.x -= movement.x;
		}

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
	int time;

	bool update()
	{
		time++;
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
	int legFrame;
	Animation animation = Animation(0.04);
	int skipFrame;

	float x = minX + 32, y = (minY + maxY) / 2;

	void draw(IRenderTarget target, bool hint)
	{
		if (animation.update)
		{
			legFrame = (legFrame + 1) % legs.length;
			skipFrame = (skipFrame + 1) % 4;
		}

		auto offX = x % 32;
		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation((x - 24),
				(y - 40 - (skipFrame >= 2 ? 1 : 0)), 0);
		if (hint)
		{
			matrixStack.push();
			matrixStack.top = mat4.translation((x - 24), (y - (skipFrame >= 2 ? 1 : 0)), 0) * mat4.scaling(1,
					-1, 1);
			target.draw(head);
			matrixStack.pop();
		}
		else
			target.draw(head);
		target.draw(arms);
		target.draw(legs[legFrame]);
		matrixStack.pop();
	}

	void move(vec2 l)
	{
		if (l.length_squared == 0)
			return;
		x = clamp(x + l.x * 0.2, minX, maxX);
		y = clamp(y + l.y * 0.4, minY, maxY);
	}

	bool hitsObstacle(ref Road r)
	{
		vec2 v = vec2(x, y);
		foreach (obstacle; r.activeObstacles)
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
			velocity = vec2((a * -1) + (d * 1), (w * -1) + (s * 1));
			break;
		case Event.Type.MouseButtonPressed:
			if (event.mousebutton == 1)
				shooting = true;
			break;
		case Event.Type.MouseButtonReleased:
			if (event.mousebutton == 1)
				shooting = false;
			break;
		case Event.Type.MouseMoved:
			aim = vec2(event.x / scale, event.y / scale);
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

vec4 uv(int left, int top, int right, int bottom)
{
	return vec4(left / 16.0, top / 16.0, right / 16.0, bottom / 16.0);
}

void main()
{
	Window window = new Window(cast(int)(maxX * scale), cast(int)(128 * scale));

	auto fps = new FPSLimiter(240);

	auto tex = new Texture("textures.png", TextureFilterMode.Nearest, TextureFilterMode.Nearest);

	auto road = Road(RectangleShape.create(tex, vec2(0, 64), vec2(32, 64), uv(7, 0, 9, 4)));

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

	RectangleShape giftRect = RectangleShape.create(tex, vec2(-8, -16),
			vec2(16, 16), uv(5, 0, 6, 1));

	int aimTime;
	RectangleShape[5] aimHelper;
	foreach (i; 0 .. 5)
		aimHelper[i] = RectangleShape.create(tex, vec2(-8, -8), vec2(16, 16), uv(i, 3, i + 1, 4));

	Gift[] gifts;

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

		frames++;

		dman.move(input.velocity);

		int aimFrame;
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
				auto end = vec2(dman.x, dman.y - aimTimeLength);
				float d = (end - input.aim).length;
				if (d > 1)
					gifts ~= Gift(end, input.aim, d);
			}
			aimTime = aimTimeLength;
		}

		road.draw(window);
		dman.draw(window, dman.hitsObstacle(road));

		foreach_reverse (i, ref gift; gifts)
		{
			gift.start -= movement;
			gift.goal -= movement;
			if ((gift.start - gift.goal).length_squared <= 1)
			{
				road.impact(gift.goal.x, gift.goal.y);
				gifts = gifts.remove(i);
				continue;
			}
			vec2 dir = gift.goal - gift.start;
			auto lenSq = dir.length_squared;
			enum giftSpeed = 0.8f;
			if (lenSq > giftSpeed * giftSpeed)
				dir = dir / sqrt(lenSq) * giftSpeed;
			matrixStack.push();
			matrixStack.top = matrixStack.top * mat4.translation(gift.start.x,
					gift.start.y - gift.z * gift.origDist * 0.2, 0);
			giftRect.draw(window);
			matrixStack.pop();
			gift.start += dir;
		}

		matrixStack.push();
		matrixStack.top = matrixStack.top * mat4.translation(input.aim.x, input.aim.y, 0);
		aimHelper[aimFrame].draw(window);
		matrixStack.pop();

		window.display();

		fps.wait();
	}
}
