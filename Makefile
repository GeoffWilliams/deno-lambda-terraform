APP_VERSION := $(shell cat VERSION)
DENO_FLAGS := --allow-net --allow-env --allow-read
HANDLER_FILE := ../app.ts

.EXPORT_ALL_VARIABLES:
.PHONY: terraform

zipfile:
	rm -rf build
	mkdir build
	cd build \
	&& deno compile -o bootstrap $(DENO_FLAGS) $(HANDLER_FILE) \
	&& zip -r app-$(APP_VERSION).zip .

terraform:
	cd terraform && terraform apply -auto-approve

destroy:
	cd terraform && terraform destroy -auto-approve