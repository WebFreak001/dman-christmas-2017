import d2d;

import std.algorithm;
import std.random;

enum scale = 4;

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

enum movement = vec2(0.45, 0);

struct House
{
	int type;
	float x;
}

struct Road
{
	RectangleShape shape;
	RectangleShape[] obstacles;
	RectangleShape[] houseTypes;
	float x = 0;

	ActiveObstacle[] activeObstacles;
	House[] houses;

	void spawnRandomHouse()
	{
		houses ~= House(uniform(0, cast(int) houseTypes.length), 192);
	}

	void draw(IRenderTarget target)
	{
		x += movement.x;

		foreach_reverse (i, ref house; houses)
		{
			if (house.x < )
		}

		auto offX = x % 32;
		matrixStack.push();
		matrixStack.top = matrixStack.top.translate(-offX * scale, 0, 0);
		foreach (i; 0 .. 192 / 32 + 1)
		{
			target.draw(shape);
			matrixStack.top = matrixStack.top.translate(32 * scale, 0, 0);
		}
		matrixStack.pop();

		if (!activeObstacles.length
				|| activeObstacles[$ - 1].pos.x < (maxX - 4) * scale && uniform(0, 50) == 0)
			activeObstacles ~= ActiveObstacle(vec2((maxX + 32) * scale, uniform(0,
					3) == 0 ? uniform(minY + 8, maxY - 8) * scale : dman.y * scale),
					cast(int) uniform(0, obstacles.length));

		foreach_reverse (i, ref obstacle; activeObstacles)
		{
			matrixStack.push();
			matrixStack.top = matrixStack.top.translate(obstacle.pos.x, obstacle.pos.y, 0);
			target.draw(obstacles[obstacle.image]);
			matrixStack.pop();
			obstacle.pos.x -= movement.x * scale;
		}
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
		matrixStack.top = matrixStack.top.translate((x - 24) * scale,
				(y - 40 - (skipFrame >= 2 ? 1 : 0)) * scale, 0);
		if (hint)
		{
			matrixStack.push();
			matrixStack.top = mat4.translation((x - 24) * scale, (y - (skipFrame >= 2 ? 1
					: 0)) * scale, 0) * mat4.scaling(1, -1, 1);
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
		vec2 v = vec2(x, y) * scale;
		foreach (obstacle; r.activeObstacles)
			if (((v - vec2(0, 1 * scale) - obstacle.pos).mul(vec2(0.5, 1))).length_squared < (
					4 * scale) ^^ 2)
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
	vec2 aim = vec2(96 * scale, 64 * scale);
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
			aim = vec2(event.x, event.y);
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

void main()
{
	Window window = new Window(192 * scale, 128 * scale);

	auto fps = new FPSLimiter(240);

	auto tex = new Texture("textures.png", TextureFilterMode.Nearest, TextureFilterMode.Nearest);

	auto road = Road(RectangleShape.create(tex, vec2(0, 64 * scale),
			vec2(32 * scale, 64 * scale), vec4(7 / 16.0, 0, 9 / 16.0, 4 / 16.0)));

	road.obstacles = [RectangleShape.create(tex, vec2(-24 * scale, -8 * scale),
			vec2(32 * scale, 16 * scale), vec4(5 / 16.0, 1 / 16.0, 7 / 16.0, 2 / 16.0)),
		RectangleShape.create(tex, vec2(-8 * scale, -8 * scale), vec2(16 * scale,
				16 * scale), vec4(6 / 16.0, 2 / 16.0, 7 / 16.0, 3 / 16.0))];

	dman.head = RectangleShape.create(tex, vec2(0, 0), vec2(32 * scale,
			32 * scale), vec4(0, 0, 2 / 16.0, 2 / 16.0));
	dman.arms = RectangleShape.create(tex, vec2(0, 0), vec2(48 * scale,
			32 * scale), vec4(2 / 16.0, 0, 5 / 16.0, 2 / 16.0));
	foreach (i; 0 .. dman.legs.length)
	{
		dman.legs[i] = RectangleShape.create(tex, vec2(16 * scale, 31 * scale),
				vec2(16 * scale, 16 * scale), vec4(i / 16.0, 2 / 16.0, (i + 1) / 16.0, 3 / 16.0));
	}

	RectangleShape giftRect = RectangleShape.create(tex, vec2(-8 * scale,
			-16 * scale), vec2(16 * scale, 16 * scale), vec4(5 / 16.0, 0, 6 / 16.0, 1 / 16.0));

	int aimTime;
	RectangleShape[5] aimHelper;
	foreach (i; 0 .. 5)
		aimHelper[i] = RectangleShape.create(tex, vec2(-8 * scale, -8 * scale),
				vec2(16 * scale, 16 * scale), vec4(i / 16.0, 3 / 16.0, (i + 1) / 16.0, 4 / 16.0));

	Gift[] gifts;

	Input input;

	Event event; // Or WindowEvent
	while (window.open)
	{
		while (window.pollEvent(event))
		{
			input.handleEvent(event);
			if (event.type == Event.Type.Quit)
				window.close();
		}
		window.clear(0.36, 0.36, 0.36);

		dman.move(input.velocity);

		int aimFrame;
		if (input.shooting)
		{
			aimTime++;
			aimFrame = aimTime / 24;
			if (aimFrame >= aimHelper.length)
				aimFrame = aimHelper.length - 1;
		}
		else
		{
			if (aimTime > aimHelper.length * 24 - 12)
			{
				auto end = vec2(dman.x, dman.y - 24) * scale;
				float d = (end - input.aim).length;
				if (d > 1)
					gifts ~= Gift(end, input.aim, d);
			}
			aimTime = 24;
		}

		road.draw(window);
		dman.draw(window, dman.hitsObstacle(road));

		foreach_reverse (i, ref gift; gifts)
		{
			gift.start -= movement * scale;
			gift.goal -= movement * scale;
			if ((gift.start - gift.goal).length_squared <= 1)
			{
				gifts = gifts.remove(i);
				continue;
			}
			vec2 dir = gift.goal - gift.start;
			auto lenSq = dir.length_squared;
			enum giftSpeed = 0.8f * scale;
			if (lenSq > giftSpeed * giftSpeed)
				dir = dir / sqrt(lenSq) * giftSpeed;
			matrixStack.push();
			matrixStack.top = matrixStack.top.translate(gift.start.x,
					gift.start.y - gift.z * gift.origDist * 0.2, 0);
			giftRect.draw(window);
			matrixStack.pop();
			gift.start += dir;
		}

		matrixStack.push();
		matrixStack.top = matrixStack.top.translate(input.aim.x, input.aim.y, 0);
		aimHelper[aimFrame].draw(window);
		matrixStack.pop();

		window.display();

		fps.wait();
	}
}
