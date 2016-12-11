function profiles_prep_main(dataset)
% profiles_prep_main(dataset)
%
%  main routine to process hydrographic data set :
%	1) read, resample vertically and save hydrographic data in the MITprof netcdf format
%	2) set quality flag, colocated climatologial data and weights for each profile
%
%  input: dataset is a struct generated by profiles_prep_select, and
%       describing the dataset that must be processed, and processing options.
%
%  Important: some important variables are set as global:
%                       mygrid mytri MYBASININDEX atlas sigma
%       These variables are loaded by the function profiles_prep_load_fields
%       However, if mygrid is non-empty, no attempt to reload these variables will
%       be made.
%

MITprof_global;
global mytri MYBASININDEX atlas sigma
global useNativeMatlabNetcdf

if isempty(myenv.verbose), myenv.verbose=0; end
if isempty(mygrid) | isempty(mytri) | isempty(MYBASININDEX) | isempty(atlas) | isempty(sigma),
    profiles_prep_load_fields;
end
if isempty(useNativeMatlabNetcdf), useNativeMatlabNetcdf = ~isempty(which('netcdf.open')); end
if ~isfield(dataset,'skipSTEP1'); dataset.skipSTEP1=0; end;
if dataset.skipSTEP1&~isfield(dataset,'fileIn'); 
  error('data.set.fileIn needs to be defined when using skipSTEP1');
end;

if ~dataset.skipSTEP1;

%% STEP 1: read, resample vertically and save hydrographic data in the MITprof netcdf format
if myenv.verbose; disp('step 1: convert into MITprof netcdf format'); end


% determine the full output file name
[pathstr, name, ext] = fileparts([dataset.dirOut dataset.fileOut]);
if isempty(pathstr) | strcmp(pathstr,'.'), pathstr=pwd; end
if isempty(ext) | ~strcmp(ext,'.nc'), ext='.nc'; end
dataset.fileOut=[name ext];

%get the list of files to be treated :
nfiles=length(dataset.fileInList);
if nfiles==0, disp('no files to process'); return, end

% init global variables used to store temporary loaded profiles
MITprofCur=profiles_prep_write_nc(dataset,[],'init');

% main loop
for nf=1:nfiles % FILE LOOP
    
    if myenv.verbose & mod(nf,10)==0,
        fprintf('%s : %04d --> %04d \n',dataset.name,nf,nfiles);
    end;
    
    
    % load file information:
    eval(['dataset=profiles_read_' dataset.name '(dataset,nf,0);']);
    
    % extract and process individual profiles
    nprofiles=dataset.nprofiles;
    for np=1:nprofiles;
        
        if myenv.verbose & mod(np,100)==0,
            fprintf('\t : %04d --> %04d\n',np,nprofiles);
        end
        
        % read 1 profile:
        eval(['profileCur=profiles_read_' dataset.name '(dataset,nf,np);']);
        if isempty(profileCur), continue, end
        
        %conversions of p->z, Tinsitu->Tpot, and 0-360 lon to -180+180 lon:
        profileCur=profiles_prep_convert(dataset,profileCur);
        
        %interpolate to standard levels:
        if strcmp(dataset.coord,'depth');
            profileCur=profiles_prep_interp(dataset,profileCur);
        else;
            %switch to isopycnal coordinate:
            profileCur=profiles_isopycnal_z(dataset,profileCur,dataset.coord);
            profileCur=profiles_isopycnal_interp(dataset,profileCur);
        end;
        
        %placeholders:
        profileCur.point=0; profileCur.basin=0;
        if ~strcmp(dataset.coord,'depth'); profileCur.depth_equi=0; end;
        for ii=2:length(dataset.var_out);
            z_std=dataset.z_std;
            eval(['profileCur.' dataset.var_out{ii} '_equi=NaN*z_std;']);
            eval(['profileCur.' dataset.var_out{ii} '_w=NaN*z_std;']);
        end;
        
        %carry basic tests:
        profileCur=profiles_prep_tests_basic(dataset,profileCur);
        
        %store/write results in global variables (and in .mat files if buffer is full):
        MITprofCur=profiles_prep_write_nc(dataset,profileCur,'add',MITprofCur);
        
    end      % LOCATION LOOP
end      % FILE LOOP

% write profiles in the MITprof netcdf file
profiles_prep_write_nc(dataset,profileCur,'write',MITprofCur);
if ~exist([dataset.dirOut dataset.fileOut],'file'), return, end

end;%if ~dataset.skipSTEP1;

%% STEP 2: set quality flag, colocated climatologial data and weights for each profile

if myenv.verbose; disp('step 2: weights and tests'); end

%test whether gcmfaces package is in the path...
gcmfacesISavailable=~isempty(which('gcmfaces'));
if ~gcmfacesISavailable;
    error('gcmfaces absent of matlab path => no atlas or weights were included');
end

%load standardized data set:
if ~dataset.skipSTEP1;
  MITprofCur=MITprof_load([dataset.dirOut dataset.fileOut]);
else;
  MITprofCur=MITprof_load([dataset.dirIn dataset.fileIn]);
end;

%add grid information (if not already done in profiles_prep_write_nc.m)
if ~dataset.addGrid;
    MITprofCur=profiles_prep_locate(dataset,MITprofCur);
end;

if ~strcmp(dataset.coord,'depth'); profiles_isopycnal_fields(dataset); end;
if ~strcmp(dataset.coord,'depth')&~isfield(MITprofCur,'prof_Terr');
    MITprofCur.prof_Terr(:)=0;
    MITprofCur.prof_Serr(:)=0;
end;
if isfield(MITprofCur,'prof_T')&~isfield(MITprofCur,'prof_Tflag');
   MITprofCur.prof_Tflag=zeros(size(MITprofCur.prof_T));
end;
if isfield(MITprofCur,'prof_S')&~isfield(MITprofCur,'prof_Sflag');
   MITprofCur.prof_Sflag=zeros(size(MITprofCur.prof_S));
end;
if isfield(MITprofCur,'prof_T');
   MITprofCur.prof_T(MITprofCur.prof_T==0)=NaN;
end;
if isfield(MITprofCur,'prof_S');
   MITprofCur.prof_S(MITprofCur.prof_S==0)=NaN;
end;

%instrumental + representation error profile:

%min T/Serr used in feb2013 version:
%MITprofCur.prof_Terr=nanmax(MITprofCur.prof_Terr,0.01);
%MITprofCur.prof_Serr=nanmax(MITprofCur.prof_Serr,0.01);

MITprofCur=profiles_prep_weights(dataset,MITprofCur,sigma);

%carry tests vs atlases:
MITprofCur.fillval=dataset.fillval;
[MITprofCur]=profiles_prep_tests_cmpatlas(dataset,MITprofCur,atlas);

%overwrite file with completed arrays:
MITprof_write([dataset.dirOut dataset.fileOut],MITprofCur);

%specify atlas names:
ncid=ncopen([dataset.dirOut dataset.fileOut],'write');
if isfield(MITprofCur,'prof_T'); ncaddAtt(ncid,'prof_Testim','long_name','pot. temp. atlas (OCCA | PHC in arctic| WOA in marginal seas)'); end;
if isfield(MITprofCur,'prof_S'); ncaddAtt(ncid,'prof_Sestim','long_name','salinity atlas (OCCA | PHC in arctic| WOA in marginal seas)'); end;
ncclose(ncid);

if ~strcmp(dataset.coord,'depth'); mygrid=[]; atlas=[]; sigma=[]; end;


