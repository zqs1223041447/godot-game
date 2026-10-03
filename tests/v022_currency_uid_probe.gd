extends "res://tests/v022_currency_acceptance_test.gd"
func run()->void:
	_no_uid_reuse()
	print("Currency identity probe: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
