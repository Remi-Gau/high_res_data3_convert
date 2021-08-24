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
  create_events_tsv_file(input_dir, output_dir, subject_label, func);
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

function create_events_tsv_file(input_dir, output_dir, subject_label, func)
    
    % onsall: (8 runs x 2 conditions x 3 trials x 2 onset/offset) - in millisecond
    % fixall: (which is redundant as the stimulus presentation is 12sec on 12 off, 
    %         so the fixation periods can be easily derived from the stimulus onset times, 
    %         but its there anyway) , which is 8 runs x 7 fixations periods x 2 onset/offs

  load(fullfile(input_dir.func, 'onsets.mat'), 'onsall');
  
  onsall = onsall / 1000; %#ok<NODEF>
  
  [nb_runs, nb_cdt, nb_trials, ~] = size(onsall);

  for run = 1:nb_runs
      
      onset_column = [];
      duration_column = [];
      trial_type_column = {};
      
      for condition = 1:nb_cdt
          
          for trial = 1:nb_trials
              
              onset = onsall(run, condition, trial, 1);
              offset = onsall(run, condition, trial, 2);
              
              onset_column = [onset_column; onset];
              duration_column = [duration_column; offset - onset];
              trial_type_column{end+1} = sprintf('condition_%i', condition);
              
          end
          
      end
      
      [onset_column, idx] = sort(onset_column);
      duration_column = duration_column(idx);
      trial_type_column = trial_type_column(idx);
      
      
      tsv_content = struct('onset', onset_column, ...
          'duration', duration_column, ...
          'trial_type', {cellstr(trial_type_column)});
      
      file = struct('suffix', 'events', ...
          'modality', 'func', ...
          'ext', '.tsv', ...
          'entities', struct('sub', subject_label, ...
          'task', func.task_name, ...
          'acq', func.acq, ...
          'run', sprintf('%i', run)));
      filename = bids.create_filename(file);
      
      bids.util.tsvwrite(fullfile(output_dir, ['sub-' subject_label], 'func', filename), ...
          tsv_content);
      
  end

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
