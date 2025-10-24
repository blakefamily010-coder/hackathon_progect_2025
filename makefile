ignore_time:
	touch space_program/ -a
	touch drumbot/ -a
hardware: hardware_c ignore_time
	mkdir -p .build/
	arduino-cli upload -b esp32:esp32:esp32c6 -p dev/ttyACM0 --build-path .build/
hardware_c:
	mkdir -p .build/
	arduino-cli compile ./hardware/ -b esp32:esp32:esp32c6 -p dev/ttyACM0 --build-path .build/
clean:
	rm -R ./.build/
