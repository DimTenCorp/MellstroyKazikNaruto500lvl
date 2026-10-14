extends RefCounted
## Константы Bridge без зависимостей: модули аддона ссылаются на них
## напрямую, поэтому аддон компилируется даже без autoload Bridge.

const DeviceType = {
	DESKTOP = "desktop",
	MOBILE = "mobile",
	TABLET = "tablet",
	TV = "tv"
}

const PlatformMessage = {
	GAME_READY = "game_ready",
	IN_GAME_LOADING_STARTED = "in_game_loading_started",
	IN_GAME_LOADING_STOPPED = "in_game_loading_stopped",
	GAMEPLAY_STARTED = "gameplay_started",
	GAMEPLAY_STOPPED = "gameplay_stopped",
	PLAYER_GOT_ACHIEVEMENT = "player_got_achievement",
	LEVEL_STARTED = "level_started",
	LEVEL_COMPLETED = "level_completed",
	LEVEL_FAILED = "level_failed",
	LEVEL_PAUSED = "level_paused",
	LEVEL_RESUMED = "level_resumed"
}

const LeaderboardType = {
	NOT_AVAILABLE = "not_available",
	IN_GAME = "in_game",
	NATIVE = "native",
	NATIVE_POPUP = "native_popup"
}

const BannerPosition = {
	TOP = "top",
	BOTTOM = "bottom"
}

const BannerState = {
	LOADING = "loading",
	SHOWN = "shown",
	HIDDEN = "hidden",
	FAILED = "failed"
}

const InterstitialState = {
	LOADING = "loading",
	OPENED = "opened",
	CLOSED = "closed",
	FAILED = "failed"
}

const RewardedState = {
	LOADING = "loading",
	OPENED = "opened",
	REWARDED = "rewarded",
	CLOSED = "closed",
	FAILED = "failed"
}

const LaunchSource = {
	NOTIFICATION = "notification",
	POST = "post"
}

const PostRewardType = {
	VISIT = "visit",
	AUTHOR = "author"
}
