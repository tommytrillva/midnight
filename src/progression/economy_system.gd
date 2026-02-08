## Manages the player's cash flow, transactions, and economic state.
## Tracks all income/expense sources for analytics and story integration.
class_name EconomySystem
extends Node

var cash: int = 0
var total_earned: int = 0
var total_spent: int = 0
var transaction_log: Array[Dictionary] = []

const MAX_LOG_SIZE := 100


func set_cash(amount: int) -> void:
	var old := cash
	cash = maxi(amount, 0)
	if old != cash:
		EventBus.cash_changed.emit(old, cash)


func earn(amount: int, source: String = "unknown") -> void:
	var old := cash
	cash += amount
	total_earned += amount
	_log_transaction("earn", amount, source)
	EventBus.cash_changed.emit(old, cash)
	EventBus.cash_earned.emit(amount, source)


func spend(amount: int, item: String = "unknown") -> bool:
	if amount > cash:
		EventBus.insufficient_funds.emit(amount)
		return false
	var old := cash
	cash -= amount
	total_spent += amount
	_log_transaction("spend", amount, item)
	EventBus.cash_changed.emit(old, cash)
	EventBus.cash_spent.emit(amount, item)
	return true


func can_afford(amount: int) -> bool:
	return cash >= amount


func get_race_payout(race_type: String, position: int, tier: int) -> int:
	## Calculate race payout based on type, position, and tier.
	var base_payouts := {
		"street_sprint": [500, 200, 100],
		"circuit": [1500, 800, 400, 200],
		"drag": [800, 300],
		"highway_battle": [1200, 0],
		"touge": [1000, 0],
		"drift": [600, 300, 150],
		"tournament": [5000, 2500, 1000, 500],
	}
	var payouts: Array = base_payouts.get(race_type, [200])
	var base := 0
	if position < payouts.size():
		base = payouts[position]

	# Scale by tier (higher tier races pay more)
	var tier_mult := 1.0 + (tier * 0.5)
	return int(float(base) * tier_mult)


func _log_transaction(type: String, amount: int, description: String) -> void:
	transaction_log.append({
		"type": type,
		"amount": amount,
		"description": description,
		"timestamp": Time.get_datetime_string_from_system(),
		"balance": cash,
	})
	if transaction_log.size() > MAX_LOG_SIZE:
		transaction_log.pop_front()


func serialize() -> Dictionary:
	return {
		"cash": cash,
		"total_earned": total_earned,
		"total_spent": total_spent,
	}


func deserialize(data: Dictionary) -> void:
	cash = data.get("cash", 0)
	total_earned = data.get("total_earned", 0)
	total_spent = data.get("total_spent", 0)
