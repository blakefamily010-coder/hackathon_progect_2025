ignore_time:
	touch hardware/ -a
hardware: hardware_c ignore_time
	mkdir -p .build/
	arduino-cli upload -b esp32:esp32:esp32 -p /dev/ttyUSB0 --build-path .build/
hardware_c:
	mkdir -p .build/
	arduino-cli compile ./hardware/ -b esp32:esp32:esp32 -p dev/ttyACM0 --build-path .build/
hardware_no_c: ignore_time
	mkdir -p .build/
	arduino-cli upload -b esp32:esp32:esp32 -p /dev/ttyUSB0 --build-path .build/
clean:
	rm -R ./.build/
connect:
	minicom -b 115200 -w -D /dev/ttyUSB0
