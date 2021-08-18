

install:
	mkdir lib -p
	git clone https://github.com/bids-standard/bids-matlab.git lib/bids-matlab
	cd lib/bids-matlab && git switch dev
	

clean:
	rm -rf lib
	rm -rf ../sub-01 ../*.json ../README ../CHANGES ../derivatives

data:
	sh createDummyDataSet.sh
	git clone git://github.com/bids-standard/bids-examples.git --depth 1
	cp bids-examples/synthetic/dataset_description.json bids-examples/synthetic/derivatives/fmriprep