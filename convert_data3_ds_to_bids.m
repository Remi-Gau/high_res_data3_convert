function convert_data3_ds_to_bids()
  %
  % Converts data3 to BIDS
  %
  % Requires BIDS-matlab
  %
  % (C) Copyright 2021 Remi Gau

  subject_label = '01';

  participant_tsv_content.participant_id = 'sub-01';
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

  task.first_onset = 12;
  task.block_onset_asynchrony = 24;
  task.nb_condition_block = 6;
  task.block_duration = 12;

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

  input_dir.anat = fullfile(working_directory, '..', 'sourcedata', 'Data3', 'structural');
  input_dir.func = fullfile(working_directory, '..', 'sourcedata', 'Data3', 'functional');
  output_dir = fullfile(working_directory, '..');

  % init raw data folders
  bids.init(output_dir, folders);
  overwrite_dataset_description(fullfile(output_dir, 'dataset_description.json'), description);
  bids.util.tsvwrite(fullfile(output_dir, 'participants.tsv'), participant_tsv_content);

  convert_func(input_dir, output_dir, subject_label, func);
  create_events_tsv_file(output_dir, subject_label, func, task);
  create_bold_json(output_dir, func, subject_label);

  convert_mp2rage(input_dir, output_dir, subject_label);

end

function convert_mp2rage(input_dir, output_dir, subject_label)

  fields_to_remove = {'InstitutionName', ... % "anonymize" dataset
                      'InstitutionAddress', ...
                      'PatientName', ... % move to participants.tsv
                      'PatientSex', ...
                      'PatientAge', ...
                      'PatientSize', ...
                      'PatientWeight', ...
                      'RepetitionTime' ... % replaced by RepetitionTimePreparation
                     };

  fields_to_add = struct('NumberShots', nan, ...
                         'MagneticFieldStrength', 7);

  % From the BIDS spec:
  %  https://bids-specification.readthedocs.io/en/stable/99-appendices/11-qmri.html#mp2rage-specific-notes
  %
  % RepetitionTimeExcitation
  % The value of the RepetitionTimeExcitation field is not commonly found in the DICOM files.
  % When accessible, the value of EchoSpacing corresponds to this metadata.
  % When not accessible, 2 X EchoTime can be used as a surrogate.

  for inv = 1:2

    pattern = sprintf('^.*INV%i.nii.gz$', inv);
    input_file = bids.internal.file_utils('FPList', input_dir.anat, pattern);

    file = struct('suffix', 'MP2RAGE', ...
                  'ext', '.nii.gz', ...
                  'use_schema', true, ...
                  'entities', struct('sub', subject_label, ...
                                     'acq', 'pt75', ...
                                     'part', 'mag'));

    file.entities.inv = num2str(inv);
    filename = bids.create_filename(file);
    output_file = fullfile(output_dir, bids.create_path(filename), filename);

    print_to_screen(input_file, output_file);
    copyfile(input_file, output_file);

    json_content = bids.util.jsondecode(strrep(input_file, '.nii.gz', '.json'));
    fields = fieldnames(fields_to_add);
    for i = 1:numel(fields)
      json_content.(fields{i}) = fields_to_add.(fields{i});
    end
    json_content.RepetitionTimeExcitation = json_content.EchoTime * 2;
    json_content.RepetitionTimePreparation = json_content.RepetitionTime;
    json_content = rmfield(json_content, fields_to_remove);

    bids.util.jsonencode(strrep(output_file, '.nii.gz', '.json'), ...
                         json_content);

  end

  % UNI image
  pattern = '^.*UNI.*.nii.gz$';
  input_file = bids.internal.file_utils('FPList', input_dir.anat, pattern);
  file = struct('suffix', 'UNIT1', ...
                'ext', '.nii.gz', ...
                'use_schema', true, ...
                'entities', struct('sub', subject_label, ...
                                   'acq', 'pt75'));

  filename = bids.create_filename(file);
  output_file = fullfile(output_dir, bids.create_path(filename), filename);

  print_to_screen(input_file, output_file);
  copyfile(input_file, output_file);

  json_content = bids.util.jsondecode(strrep(input_file, 'UNI.nii.gz', 'UNI_Images.json'));
  json_content = rmfield(json_content, fields_to_remove);

  bids.util.jsonencode(strrep(output_file, '.nii.gz', '.json'), ...
                       json_content);

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

    print_to_screen(input_file, output_file);
    copyfile(input_file, output_file);

  end

end

function create_events_tsv_file(output_dir, subject_label, func, task)

  onset_column = task.first_onset: ...
      task.block_onset_asynchrony: ...
      (task.nb_condition_block * task.block_onset_asynchrony);
  duration_column = repmat(task.block_duration, [task.nb_condition_block, 1]);

  % a bit of hard coding left here [:-(]
  trial_type_column = repmat(['a'; 'b'], [task.nb_condition_block / 2, 1]);

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

function create_readme()

  % Summary
  %
  % 18 Files, 2.69GB
  % 1 - Subject
  % 1 - Session
  %
  % Available Tasks
  %
  % taskAB
  %
  % Available Modalities
  %
  % MRI

end

function print_to_screen(input_file, output_file)
  fprintf(1, '\n%s --> %s\n', input_file, output_file);
end
