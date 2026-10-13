class_name SlotReel
extends Control
## Один барабан слота: колонка из ROWS видимых ячеек с бесконечной прокруткой.
## Ячейки (TextureRect Cell0..Cell3) лежат в сцене game.tscn; скрипт только
## двигает ленту. Символы едут сверху вниз; при остановке лента подаёт заданные
## символы и делает небольшой отскок, как настоящая механика барабана.

signal stopped

const CELL_INSET := 4.0    ## отступ символа от краёв ячейки (символы не слипаются)
const STEP_TIME := 0.075   ## секунды на один шаг ленты (скорость прокрутки)
const BOUNCE_TIME := 0.32  ## длительность отскока при остановке
const BOUNCE_DEPTH := 0.32 ## отскок в долях высоты ячейки
const BUFFER := 1          ## скрытых ячеек над видимой областью

var cell_size := Vector2.ZERO
var textures: Array[Texture2D] = []
var rng: RandomNumberGenerator
## Три видимых символа (сверху вниз) в состоянии покоя.
var symbols: Array[int] = [0, 0, 0]

var _cells: Array[TextureRect] = []
var _offset := 0.0
var _state := "idle"  # idle | spin | bounce
var _stop_queue: Array[int] = []
var _final: Array[int] = []
var _bounce_t := 0.0


func _ready() -> void:
	for ch in get_children():
		if ch is TextureRect:
			_cells.append(ch)
	cell_size = Vector2(size.x, size.y / float(SlotData.ROWS))
	_offset = -cell_size.y * BUFFER
	_apply()


## Выдать барабану текстуры символов и генератор случайных чисел.
func configure(p_textures: Array[Texture2D], p_rng: RandomNumberGenerator) -> void:
	textures = p_textures
	rng = p_rng


## Мгновенно показать символы (3 штуки, сверху вниз).
func set_symbols(final: Array[int]) -> void:
	symbols = final.duplicate()
	_cells[0].texture = textures[SlotData.random_symbol(rng)]
	for i in SlotData.ROWS:
		_cells[i + BUFFER].texture = textures[symbols[i]]
	_offset = -cell_size.y * BUFFER
	_state = "idle"
	_stop_queue.clear()
	_apply()


func start_spin() -> void:
	_stop_queue.clear()
	_state = "spin"


func is_spinning() -> bool:
	return _state != "idle"


## Запланировать остановку на заданных трёх символах (сверху вниз).
func stop_at(final: Array[int]) -> void:
	_final = final.duplicate()
	# Лента подаёт их снизу вверх: последним в окно заходит верхний символ.
	_stop_queue = [final[2], final[1], final[0], -1]


func _process(delta: float) -> void:
	match _state:
		"spin":
			_offset += (cell_size.y / STEP_TIME) * delta
			while _offset >= 0.0:
				_offset -= cell_size.y
				_shift()
				if _state != "spin":
					break
			_apply()
		"bounce":
			_bounce_t += delta / BOUNCE_TIME
			if _bounce_t >= 1.0:
				_offset = -cell_size.y * BUFFER
				_state = "idle"
				_apply()
				stopped.emit()
			else:
				_offset = -cell_size.y * BUFFER \
						+ sin(_bounce_t * PI) * cell_size.y * BOUNCE_DEPTH
				_apply()


func _shift() -> void:
	var feed: int
	if _stop_queue.is_empty():
		feed = SlotData.random_symbol(rng)
	else:
		feed = _stop_queue.pop_front()
		if feed < 0:
			feed = SlotData.random_symbol(rng)
		if _stop_queue.is_empty():
			# Лента встала на итоговые символы — отскок и остановка.
			symbols = _final.duplicate()
			_state = "bounce"
			_bounce_t = 0.0
	for i in range(_cells.size() - 1, 0, -1):
		_cells[i].texture = _cells[i - 1].texture
	_cells[0].texture = textures[feed]


func _apply() -> void:
	for i in _cells.size():
		_cells[i].position = Vector2(CELL_INSET, i * cell_size.y + _offset + CELL_INSET)
