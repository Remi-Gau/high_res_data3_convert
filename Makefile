

install:
	mkdir lib -p
	git clone https://github.com/bids-standard/bids-matlab.git lib/bids-matlab
	cd lib/bids-matlab && git switch dev
	

clean:
	rm -rf lib
	rm -rf ../sub-01 ../*.json ../README ../CHANGES ../derivatives

clean_data:
	rm -rf ../sub-01 ../*.json ../README ../CHANGES ../derivatives

data:
	sh createDummyDataSet.sh
	git clone git://github.com/bids-standard/bids-examples.git --depth 1
	cp bids-examples/synthetic/dataset_description.json bids-examples/synthetic/derivatives/fmriprep

convert:
	matlab -nodisplay -nosplash -nodesktop -r "run('convert_data3_ds_to_bids.m');exit;"

# to make an 'un-datalad-ed' zipped version of the dataset
# I am sure there a prettier way to do this.
zip:
	mkdir ../../Data3_v -p
	cp -R -L -v ../code ../../Data3_v/code
	cp -R -L -v ../derivatives ../../Data3_v/derivatives
	cp -R -L -v ../sub-01 ../../Data3_v/sub-01
	cp -R -L -v ../CHANGES ../../Data3_v
	cp -R -L -v ../README ../../Data3_v
	cp -R -L -v ../*.json ../../Data3_v
	cp -R -L -v ../*.tsv ../../Data3_v
	sudo chmod -R +r+w ../../Data3_v