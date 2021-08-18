function convert_data3_ds_to_bids()
  %
  % Converts data3 to BIDS
  %
  % Requires BIDS-matlab
  %
  % (C) Copyright 2021 Remi Gau

  subject_label = '01';
  
  participant_tsv_content.participant_id = '01';
  participant_tsv_content.gender = 'M';
  participant_tsv_content.age = 33;
  participant_tsv_content.height = 1.85;
  participant_tsv_content.weight = 90;

  scanner.manufacturer = 'Siemens';
  scanner.model = 'Magnetom';
  scanner.field_strength = 7;

  func = scanner;
  func.task_name = 'taskAB';
  func.repetition_time = 1.35;
  func.acq = 'pt8';
  func.nb_runs = 8;

  description = struct( ...
                       'BIDSVersion', '1.6.0', ...
                       'Name', '???', ...
                       'DatasetType', 'raw');

  folders = struct('subjects', ['sub-' subject_label], ...
                   'sessions', '', ...
                   'modalities', {{'anat', 'func'}});

  working_directory = fileparts(mfilename('fullpath'));

  addpath(fullfile(working_directory, 'lib', 'bids-matlab'));

  if isempty(which('bids.layout'))
    error('run "make install"');
  end

  input_dir.anat = fullfile(working_directory, '..', 'source', 'Data3', 'structural');
  input_dir.func = fullfile(working_directory, '..', 'source', 'Data3', 'functional');
  output_dir = fullfile(working_directory, '..');

  % init raw data folders
  bids.init(output_dir, folders);
  overwrite_dataset_description(fullfile(output_dir, 'dataset_description.json'), description);

  % init derivatives data folders for UNI image
  folders.modalities = 'anat';
  bids.util.mkdir(get_derivatives_dir(output_dir, scanner));
  bids.init(get_derivatives_dir(output_dir, scanner), folders);
  description.DatasetType = 'derivative';
  overwrite_dataset_description(fullfile(get_derivatives_dir(output_dir, scanner), ...
                                         'dataset_description.json'), ...
                                description);
  delete(fullfile(get_derivatives_dir(output_dir, scanner), 'README'));

  convert_func(input_dir, output_dir, subject_label, func);
  create_events_tsv_file(output_dir, subject_label, func);
  create_bold_json(output_dir, func, subject_label);

end

function derivatives_dir = get_derivatives_dir(output_dir, scanner)
  derivatives_dir = fullfile(output_dir, 'derivatives', scanner.manufacturer);
end

function convert_mp2rage(input_dir, output_dir, opt, subject_label, anat)
    
    fields_to_remove = {'InstitutionName', ...
    'InstitutionAddress', ...
    'PatientName',
	'PatientSex', ... 
	'PatientAge', ...
	'PatientSize', ...
	'PatientWeight')

  fields_to_remove_to_add = struct(
                        'RepetitionTimeExcitation', nan, ...
                        'RepetitionTimePreperation', nan, ...
                        'NumberShots', nan, ...
                        'MagneticFieldStrength', 7);

  %     └── sub-01/
  %      └── anat/
  %          ├── sub-01_inv-1_part-mag_MP2RAGE.nii.gz
  %          ├── sub-01_inv-1_part-phase_MP2RAGE.nii.gz
  %          ├── sub-01_inv-1_MP2RAGE.json
  %          ├── sub-01_inv-2_part-mag_MP2RAGE.nii.gz
  %          ├── sub-01_inv-2_part-phase_MP2RAGE.nii.gz
  %          └── sub-01_inv-2_MP2RAGE.json
  %
  %
  %      ds-example/
  %      └── derivatives/
  %          └── Siemens/
  %              └── sub-01/
  %                  └── anat/
  %                      ├── sub-01_UNIT1.nii.gz
  %                      └── sub-01_UNIT1.json

  for inv = 1:2
      
          pattern = sprintf('^.*run%i.nii.gz$', iRun);
    input_file = bids.internal.file_utils('FPList', input_dir.func, pattern);
  
  file = struct('suffix', 'MP2RAGE', ...
      'acq', 'pt75', ...
                'ext', '.nii.gz', ...
                'use_schema', true, ...
                'entities', struct('sub', subject_label, ...
                                   'part', 'mag'));

  filename = bids.create_filename(file);
  output_file = fullfile(output_dir, bids.create_path(filename), filename);

  bids.util.jsonencode(strrep(output_file, 'nii.gz', '.json'), ...
                       json_content);

  copyfile(input_file, output_file);
  
  end
  
end

function convert_func(input_dir, output_dir, subject_label, func)

  for iRun = 1:func.nb_runs

    pattern = sprintf('^.*run%i.nii.gz$', iRun);
    input_file = bids.internal.file_utils('FPList', input_dir.func, pattern);

    file = struct('suffix', 'bold', ...
                  'ext', '.nii.gz', ...
                  'use_shema', true, ...
                  'entities', struct('sub', subject_label, ...
                                     'acq', func.acq, ...
                                     'task', func.task_name, ...
                                     'run', num2str(iRun)));
    filename = bids.create_filename(file);

    output_file = fullfile(output_dir, bids.create_path(filename), filename);

    copyfile(input_file, output_file);

  end

end

function create_events_tsv_file(output_dir, subject_label, func)

  first_onset = 12;
  block_onset_asynchrony = 24;
  nb_condition_block = 6;

  onset_column = first_onset:block_onset_asynchrony:(nb_condition_block * block_onset_asynchrony);
  duration_column = repmat(12, [nb_condition_block, 1]);
  trial_type_column = repmat(['a'; 'b'], [nb_condition_block / 2, 1]);

  tsv_content = struct('onset', onset_column, ...
                       'duration', duration_column, ...
                       'trial_type', {cellstr(trial_type_column)});

  file = struct('suffix', 'events', ...
                'modality', 'func', ...
                'ext', '.tsv', ...
                'entities', struct('sub', subject_label, ...
                                   'task', func.task_name));
  filename = bids.create_filename(file);

  bids.util.tsvwrite(fullfile(output_dir, ['sub-' subject_label], 'func', filename), ...
                     tsv_content);

end

function overwrite_dataset_description(filename, description)

  bids.util.jsonencode(filename, description);

end

function create_bold_json(output_dir, func, subject_label)

  file = struct('suffix', 'bold', ...
                'modality', 'func', ...
                'ext', '.json', ...
                'use_schema', true, ...
                'entities', struct('sub', subject_label, ...
                                   'task', func.task_name));

  json_content = struct('Manufacturer', func.manufacturer, ...
                        'ManufacturersModelName', func.model, ...
                        'MagneticFieldStrength', func.field_strength, ...
                        'RepetitionTime', func.repetition_time, ...
                        'TaskName', func.task_name);

  filename = bids.create_filename(file);
  bids.util.jsonencode(fullfile(output_dir, ['sub-' subject_label], 'func', filename), ...
                       json_content);

end
