clear
clc
clf
close all

disp("Step zero")

% Set working directory for the bird recording session
Work_Dir = "";
cd(Work_Dir)

% Extract Bird ID from the directory path
ID=split(Work_Dir,"\");
ID=ID(end-1);

% Check for required files
[File_Check_Table,All_Neccessary_Exists]=Check_Syntax_Files(ID,Work_Dir);

% Attempt to use GPU device
try
    RTX=gpuDevice(1);
    RTX.CachePolicy="maximum";
catch
    % If no GPU is available, proceed using CPU
end

% Get Bird ID and list of day directories
[Bird_ID,Dir_Path]=Step_Zero(Work_Dir);

% Setup figure layout
% [1–3] Fortemplate .wav spectrogram
% [4] Sample motif
% [5,9] Unsorted motifs
% [6,10] Clustered motifs
% [7,11] Classified motifs
% [8,12] Metadata

tiledlayout (3,4)
%   1  2   3   4
%   5  6   7   8
%   9  10  11  12

disp("Step one")
% Read template source WAV file and calculate sonogram, then
% check if template file exists or needs to be created
Template_Source_Address = fullfile(Work_Dir,'../fortemplate.wav');
[Mic_TS,FS_TS]= audioread(Template_Source_Address);
[Template_Source, F, Data_TS] = zftftb_pretty_sonogram(Mic_TS, FS_TS,...
    'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);
nexttile(4,[1,1])
if ~File_Check_Table{1,1,5}
    % Create new template
    nexttile
    [Motif_Template,Motif_Template_Time_Bins] = Get_Mic_Template_V5(Mic_TS,FS_TS);
    save(File_Check_Table{1,1,1},'Motif_Template','FS_TS','Motif_Template_Time_Bins');
else
    % Load existing template
    load(File_Check_Table{1,1,1},'Motif_Template','FS_TS','Motif_Template_Time_Bins')
    Mic_Template_Var=whos('-file',File_Check_Table{1,1,1});
    if ~ismember('FS_TS',convertCharsToStrings({Mic_Template_Var.name}))
        FS_TS=48000;
        save(fullfile(Work_Dir,'../mic_template.mat'),'Motif_Template','FS_TS')
    end
end
Motif_Variables=whos('-file',File_Check_Table{1,1,1});
if ~ismember("Motif_Template_Time_Bins",convertCharsToStrings({Motif_Variables.name}))
    load(File_Check_Table{1,1,1},'Motif_Template','FS_TS')
    [~, ~, Motif_Template_Time_Bins] = zftftb_pretty_sonogram(Mic_TS, FS_TS,...
        'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);
    save(File_Check_Table{1,1,1},'Motif_Template_Time_Bins',"-append")
end


% Plot the full template sonogram
nexttile(1,[1,3])
imagesc(Data_TS,F,Template_Source,[prctile(Template_Source(:),1) max(1,prctile(Template_Source(:),99))])
hold on
axis tight
colormap hot
set(gca,'YDir','Normal')
title(Bird_ID+" Fortemplate")
ylabel('Frequency (Hz)')
xlabel('Time (seconds)')
hold off

% Plot the motif-only spectrogram
[Motif_Spec, F, Data_TS] = zftftb_pretty_sonogram(Motif_Template, FS_TS,...
    'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);
nexttile(4,[1,1])
imagesc(Data_TS,F,Motif_Spec,[prctile(Motif_Spec(:),1) max(1,prctile(Motif_Spec(:),99))])
hold on
axis tight
colormap hot
set(gca,'YDir','Normal')
title('Sample Motif')
ylabel('Frequency (Hz)')
xlabel('Time (seconds)')
C=xlim;
xline(C(2)/2,'-b')
hold off
Re_Analyze_Each_Day=input("Redo each day analysis? [0 1]");
Correct_Clustering=input("Correct_Clustering?");

%% Step 2: Go into each folder and find WAV files with motifs using template
disp("Step two")
Threshold = 0.5;  %threshold for finding template in wav file
for Day=1:size(Dir_Path,1)%:-1:1
    % Path to current day's folder and motif output file
    Day_Folder= fullfile(Work_Dir,Dir_Path(Day).name);
    Motifs_Syntax_File = fullfile(Day_Folder,'Motifs_Syntax.mat');
    disp(['Scanning day ' Dir_Path(Day).name])
    % Check if Motifs_Syntax.mat exists and contains required variables
    try
        Motif_Syntax_Variables=whos('-file',Motifs_Syntax_File);
        Variables_Missing=~ismember("Motifs_Anno",convertCharsToStrings({Motif_Syntax_Variables.name}));
    catch
        Variables_Missing=1;
    end

    % If file missing, outdated, or if re-analyzing, begin processing
    if ~exist(Motifs_Syntax_File,'file') || Re_Analyze_Each_Day || ~isempty(dir(fullfile(Day_Folder,'*.wav')))||Variables_Missing

        % Create subfolders
        Songs_Folder=fullfile(Day_Folder,'Songs');
        mkdir(Songs_Folder)
        Noise_Folder=fullfile(Day_Folder,'Noise_Calls');
        mkdir(Noise_Folder)

        % Move unsorted .wav files into Songs folder
        Unsorted_Wavs = dir(fullfile(Day_Folder,'*.wav'));
        for Wav=1:size(Unsorted_Wavs,1)
            try
                movefile(fullfile(Unsorted_Wavs(Wav).folder,Unsorted_Wavs(Wav).name),Songs_Folder)
            catch
            end
        end

        % Optionally move Noise_Calls back into Songs folder for reanalysis
        if Re_Analyze_Each_Day
            Unsorted_Wavs = dir(fullfile(Noise_Folder,'*.wav'));
            for Wav=1:size(Unsorted_Wavs,1)
                try
                    movefile(fullfile(Unsorted_Wavs(Wav).folder,Unsorted_Wavs(Wav).name), Songs_Folder)
                catch
                end
            end
        end

        % Unzip any zipped song folders
        Zip_Folders_Of_Songs = dir(fullfile(Day_Folder,'Songs/*.zip'));
        if ~isempty(Zip_Folders_Of_Songs)
            try
                unzip(fullfile(Songs_Folder,Zip_Folders_Of_Songs(1).name),'Songs/');
            catch
                disp("No zipped file in song folder.")
            end
        end

        % List all song .wav files
        Wav_Files = dir(fullfile(Songs_Folder,'*.wav'));
        if isempty(Wav_Files)
            continue
        end
        Number_Wav_Files=size(Wav_Files,1);
        Noise_Tracker=0;

        % Setup motif annotation containers
        Motifs_Anno1 = cell(1);
        Motifs_Anno2 = cell(1);
        Motifs_Anno3 = cell(1);
        Motifs_Anno4 = cell(1);
        Motifs_Anno5 = cell(1);

        for Wav=1:Number_Wav_Files
            File_Path = fullfile(Wav_Files(Wav).folder,Wav_Files(Wav).name);

            % Load audio file, optionally onto GPU
            try
                [Signal_GPU,FS_Wav] = audioread(File_Path);
                Signal_GPU = GpuArray(Signal_GPU); % Move to GPU
            catch
                try
                    [Signal_GPU,FS_Wav] = audioread(File_Path);
                catch
                    Noise_Tracker=Noise_Tracker+1;
                    movefile(fullfile(Songs_Folder,Wav_Files(Wav).name), Noise_Folder)
                    continue
                end
            end

            % Generate spectrogram
            [Obs_Spec, F, Time_Bins] = zftftb_pretty_sonogram(normalize(double(Signal_GPU), 'range'), FS_Wav,...
                'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);

            % Compute cross-correlation with motif template
            Match_Score = normxcorr2(Motif_Spec(50:400,:),Obs_Spec(50:400,:));
            [~,Top_Match] = max(max(Match_Score,[],2));
            Match_Score = Match_Score(Top_Match,:);

            % Detect motif peaks above threshold
            %Find maximum correlation
            %Minimum peak separation, specified as a positive real scalar.
            % When you specify a value for 'MinPeakDistance', the algorithm
            % chooses the tallest peak in the signal and ignores all peaks
            % within 'MinPeakDistance' of it. All hail gerrik,
            % he is our savior lord and greatest of all time.
            % The function then repeats
            % the procedure for the tallest remaining peak and iterates
            %until it runs out of peaks to consider.
            [Peaks,Top_Match] = findpeaks(Match_Score,'MinPeakProminence',Threshold);
            Peaks(Top_Match>numel(Time_Bins)) = [];
            Top_Match(Top_Match>numel(Time_Bins)) = [];

            Time_Per_Step = 1; %How much time per step of spectrogram.
            Timestep_Per_Sample = median(diff(Time_Bins)); %Seconds per bin

            Motif_Half_Time=fix(size(Motif_Spec,2)/2); % Half the bins in motif template
            % Motif_Half_Time=Motif_Half_Time*(median(diff(Motif_Template_Time_Bins)));%*Bins times the time difference in samples. Should get seconds.
            % Motif_Half_Time=Motif_Half_Time/Timestep_Per_Sample; %Seconds divided by the seconds per bin of detected motif.
            Motif_Padding= 1.5*fix(Time_Per_Step/Timestep_Per_Sample)+Motif_Half_Time;

            % If motif is detected
            if ~isempty(Top_Match)
                disp(['Calculating spectrogram on song ' mat2str(Wav) ' out of ' mat2str(size(Wav_Files,1))])
                Spec_Env = sum(Obs_Spec,1);
                Top_Match = reshape(Top_Match,[],1);
                Peaks = reshape(Peaks,[],1);
                % Generate spectrogram windows around detected peaks
                % Cut out the motif and a second before and after it, and save it.

                Indeces_Of_Motif_samples = repmat(-Motif_Padding:Motif_Padding,[numel(Top_Match),1]);
                % repmat(-size(Fortemplate,2)-1.5*fix(tpad/tdel):1.5*fix(tpad/tdel),[numel(ind),1])
                Top_Match = fix(repmat(Top_Match,[1,size(Indeces_Of_Motif_samples,2)])+Indeces_Of_Motif_samples);
                % Remove out-of-bounds matches
                Peaks(min(Top_Match,[],2)<1,:)=0;
                Top_Match(min(Top_Match,[],2)<1,:)=[];
                Peaks(Peaks==0) = [];
                Peaks(max(Top_Match,[],2)>numel(Spec_Env),:) = 0;
                Top_Match(max(Top_Match,[],2)>numel(Spec_Env),:) = [];
                Peaks(Peaks==0) = [];

                % Store annotations
                Motifs_Anno1{Wav,1} = [min(Top_Match,[],2),max(Top_Match,[],2)]; %when signal was detected.
                Motifs_Anno2{Wav,1} = Spec_Env(Top_Match);
                Motifs_Anno3{Wav,1} = Peaks;
                Motifs_Anno4{Wav,1} = repmat(Wav,[numel(Peaks),1]);
                Motifs_Anno5{Wav,1} = Wav_Files(Wav).name;
            else
                % If no motif found, move to noise folder
                movefile(fullfile(Songs_Folder,Wav_Files(Wav).name), Noise_Folder)
                Noise_Tracker=Noise_Tracker+1;
            end
        end
        disp("Percent songs moved to noise "+ string(Noise_Tracker/Number_Wav_Files));

        % Save all motif annotations for this day
        Motifs_Anno = gather(cat(2,Motifs_Anno1,Motifs_Anno2,Motifs_Anno3,Motifs_Anno4,Motifs_Anno5));
        save(Motifs_Syntax_File,'Motifs_Anno','Template_Source','Threshold','-v7.3')
    end
end

%% Step 3: Display spectrograms and cluster motifs
disp("Step three")

% Load all .mat files containing motifs (1 per day)
Syntax_Folder = fullfile(Work_Dir,'syntax_analysis');
if ~File_Check_Table{3,1,5}
    mkdir(Syntax_Folder)
    Missed_Motif=0;
    Motifs_Anno_Agg=cell(1,5);
    for Day=1:size(Dir_Path,1)%:-1:1
        disp(['Loading motifs for syntax analysis ' Dir_Path(Day).name])
        Day_Folder = fullfile(Work_Dir,Dir_Path(Day).name,'Motifs_Syntax.mat');
        try
            % Extract motif metadata from each file
            Motif_Syntax_Variables=whos('-file',Day_Folder);
            if ~ismember("Motifs_Anno",convertCharsToStrings({Motif_Syntax_Variables.name}))
                 disp("Missed a motif_syntax.mat")
            Missed_Motif=Missed_Motif+1;
                continue
            end
            load(Day_Folder,'Motifs_Anno')
            Mark_Empty = cellfun(@isempty, Motifs_Anno(:,2));
            Motifs_Anno(Mark_Empty,:)=[];
            Motifs_Anno_Agg = cat(1,Motifs_Anno_Agg,Motifs_Anno);
        catch
            disp("Missed a motif_syntax.mat")
            Missed_Motif=Missed_Motif+1;
            continue
        end
    end

    Motifs_Anno_Agg(1,:) = [];
    Motifs_Anno_Agg(cellfun(@isempty,Motifs_Anno_Agg(:,1)),:) = [];
    Total_Motif_Anno = cat(1,Motifs_Anno_Agg{:,2});
    % Keep half of the motifs, that are the loudest.
    [~,Loud_Index] = sort(sum(Total_Motif_Anno,2),'descend');
    Loud_Index = Loud_Index(1:fix(numel(Loud_Index)./2));
    % save("motif_syntax_library_variables.mat","loudIndex","Missed_motif","motifEnvelope")
    Total_Motif_Anno = Total_Motif_Anno(Loud_Index,:);
    %Create unsorted motif graphic
    nexttile(5,[2,1])
    hold on
    imagesc(Total_Motif_Anno)
    axis tight
    title("Motifs Unsorted")
    Figure_Xaxis_Range=xlim;
    xline(Figure_Xaxis_Range(2)/2,'LineWidth',1,'Color','b')                %Middle of motif
    %Cluster based on center
    disp('Select region for clustering.')
    % do not move on until enter key is pressed
    Clust_Select= fix(getrect());
    xline(Clust_Select(1),'LineWidth',1,'Color','w')
    xline(Clust_Select(1)+Clust_Select(3),'LineWidth',1,'Color','w')
    disp("gotrect")
    hold off
    Total_Motif_Anno = gather(Total_Motif_Anno(:,Clust_Select(1):( Clust_Select(1)+Clust_Select(2)))); %Signal between time points.
    Motif_Cluster_Index = clusterdata(Total_Motif_Anno,'Linkage','ward','SaveMemory','on','Maxclust',25);    %Cluster data
    save(File_Check_Table{3,1,1},'Motifs_Anno_Agg','Total_Motif_Anno','Motif_Cluster_Index','Loud_Index','Clust_Select','Missed_Motif','-mat')
else
    load(File_Check_Table{3,1,1})
    Total_Motif_Anno_Agg = cat(1,Motifs_Anno_Agg{:,2});
    Total_Motif_Anno_Agg = Total_Motif_Anno_Agg(Loud_Index,:);
    nexttile(5,[2,1])
    imagesc(Total_Motif_Anno_Agg)
    hold on
    axis tight
    title("Motifs Unsorted")
    Figure_Xaxis_Range=xlim;
    xline(Figure_Xaxis_Range(2)/2,'LineWidth',1,'Color','b')%Middle of motif
    %Cluster based on center
    disp('select region to use for clustering end notes')
    xline(Clust_Select(1),'LineWidth',1,'Color','w')
    xline(Clust_Select(1)+Clust_Select(3),'LineWidth',1,'Color','w')
    hold off
end

% Cluster and classify motifs (e.g., using t-SNE, K-means, etc.)
Motif_Envelope = cat(1,Motifs_Anno_Agg{:,2});
Motif_Envelope = Motif_Envelope(Loud_Index,:);
Number_Of_Clusters=max(Motif_Cluster_Index);
Cluster_Data = cell(max(Motif_Cluster_Index),3);

for Wav=1:Number_Of_Clusters
    disp(Wav)
    tmp = Motif_Envelope(Motif_Cluster_Index==Wav,:);%Assign motif based on cluster number
    Cluster_Data{Wav,1} = tmp;               %The sum line of the detected motif
    Cluster_Data{Wav,2} = mean(tmp,1);
    Cluster_Data{Wav,3} = find(Motif_Cluster_Index==Wav) ;%Find indexes of where in motif cluster index theres a matching motif for cluster I;
end

disp("Making figures")
Resorted_Motif = cat(1,Cluster_Data{:,1});%Motifs resorted into clusters
Clustered_Height = cellfun(@length,Cluster_Data(:,3));
Clustered_Height = cumsum(Clustered_Height);
T2 = (1:size(Resorted_Motif,2))./1000;

nexttile(6,[2,1])
hold on
% imagesc(T2,[],Resorted_Motif)%,[prctile(Resorted_Motif(:),1) prctile(Resorted_Motif(:),99)])
imagesc(Resorted_Motif,[prctile(Resorted_Motif(:),1) prctile(Resorted_Motif(:),99)])

Figure_Xaxis_Range=xlim;
xline(Figure_Xaxis_Range(2)/2,'LineWidth',1,'Color','b')                %Middle of motif
xline((Figure_Xaxis_Range(2)/2)-(width(Data_TS)/2),'LineWidth',2,'Color','w') %Start of motif
xline((Figure_Xaxis_Range(2)/2)+(width(Data_TS)/2),'LineWidth',2,'Color','w') %End of motif
yticks(unique(Clustered_Height))
yticklabels({1:25})
for Wav=1:numel(Clustered_Height)
    yline(Clustered_Height(Wav),'LineWidth',1,'Color','w')
end
colormap hot
ylabel('Clusters')
% xlabel('Time (sec)')
title('Clustered Motifs')
axis tight

hold off
%% step 4 select Calssify clusters
if ~exist('Correct_Clustering','var')
    Correct_Clustering=input("Correct_Clustering?");
end

Cluster_Index_Address=fullfile(Work_Dir,'syntax_analysis','Cluster_Index.mat');
if ~isfile(Cluster_Index_Address)||Correct_Clustering
    Cluster_Index=input("Classify clusters using the following format examples."+ ...
        "\n {{1,2,3,4},{5,6,7},{8,9},{13}} {{First},{Degraded},{Failure},{Corrected}} \n \n")';
    Cluster_Index{1,3} = strjoin(string(Cluster_Index{1,1}'),",");
    Cluster_Index{2,3} = strjoin(string(Cluster_Index{2,1}'),",");
    Cluster_Index{3,3} = strjoin(string(Cluster_Index{3,1}'),",");
    Cluster_Index{4,3} = strjoin(string(Cluster_Index{4,1}'),",");

    %add label to each cluster
    Cluster_Index{1,2} = "First";
    Cluster_Index{2,2} = "Degraded";
    Cluster_Index{3,2} = "Failure";
    Cluster_Index{4,2} = "Corrected";
    Cluster_Index(cellfun(@isempty,Cluster_Index(:,1)),:) = [];
    save(Cluster_Index_Address,'Cluster_Index')
else
    load(Cluster_Index_Address)
end
Selected_Clusters = cell(1);%
for j=1:size(Cluster_Index,1)
    Selected_Clusters{j,1} = find(ismember(Motif_Cluster_Index,Cluster_Index{j,1})==1);
end
Motifs_Anno_Agg(cellfun(@isempty,Motifs_Anno_Agg(:,1)),:) =[];
%remove motis preceded by silence

Cluster_Data = cell(1);
Signal_GPU = cat(1,Motifs_Anno_Agg{:,2}); %Slow down point.
Signal_GPU = Signal_GPU(Loud_Index,:);

%Sort motifs by similarity to absolute motif
Motif_Sim_Cmpr_Template = cat(1,Motifs_Anno_Agg{:,3});
Motif_Sim_Cmpr_Template = Motif_Sim_Cmpr_Template(Loud_Index,:);
for Wav=1:size(Selected_Clusters,1)
    tmp = Signal_GPU(Selected_Clusters{Wav,1},:);
    [~,Top_Match] =sort(Motif_Sim_Cmpr_Template(Selected_Clusters{Wav,1},1),'descend');
    Cluster_Data{Wav,1} = tmp;
    Cluster_Data{Wav,2} = mean(tmp(Top_Match,:),1);
    Cluster_Data{Wav,3} = Motif_Sim_Cmpr_Template(Selected_Clusters{Wav,1},1);
    Cluster_Data{Wav,4} = Selected_Clusters{Wav,1}(Top_Match);
end
Resorted_Motif = cat(1,Cluster_Data{:,1});
Clustered_Height = cellfun(@length,Cluster_Data(:,3));
Clustered_Height = cumsum(Clustered_Height);
Something1=1;
Something2=[round(100*[Clustered_Height(1);diff(Clustered_Height)]/Clustered_Height(end),2)]';
for Wav =1:size(Cluster_Index,1)
    if isempty(Cluster_Index{Wav,1})
        Cluster_Index{Wav,1}=0;
    else
        Cluster_Index{Wav,1}=Something2(Something1);
        Something1=Something1+1;
    end
end

nexttile(7,[2,1])
imagesc(Resorted_Motif,[prctile(Resorted_Motif(:),1) prctile(Resorted_Motif(:),99)])
hold on
colormap hot
Figure_Xaxis_Range=xlim;
xline(Figure_Xaxis_Range(2)/2,'LineWidth',1,'Color','b')
colorbar
for Wav=1:height(Cluster_Index)
    yline(Clustered_Height(Wav),'LineWidth',2,'Color','w')
end
ylabel('Classifications')
xlabel('Seconds')
yticks(Clustered_Height)
for Wav=1:height(Cluster_Index)
    yline(Clustered_Height(Wav),'LineWidth',2,'Color','w')
end
title("Clustered Motifs")
yticklabels([Cluster_Index{:,2}])
hold off
saveas(gca,"D:\Lab Dropbox\Shared_Gerrik\Code\DLC_coordinates\image13.svg",'svg')

Class_Percentages=[Cluster_Index{:,2}]'+" "+[Cluster_Index{:,1}]'+"% From cluster(s):"+[Cluster_Index(:,3)] ;

Report_Table=cat(2,["Days recorded "+size(Dir_Path,1),"Motifs classified "+size(Resorted_Motif,1),"Days unclassified "+Missed_Motif],Class_Percentages');
annotation('textbox',[0.75 0 0.2 0.6],'String',Report_Table,'FitBoxToText','on','Color','red');

set(gcf, 'Position', get(0, 'Screensize'))
saveas(gcf,fullfile(Syntax_Folder,Bird_ID+"_Motif_Syntax_Summary.svg"),'svg')

function [Bird_ID,Dir_Path]=Step_Zero(Work_Dir)
Bird_ID=strsplit(Work_Dir,"\");
Bird_ID=Bird_ID{end-1};
cd(Work_Dir)
%Get all day folders
Dir_Path = dir();
%Remove nonday folders
Dir_Path(1:2) = [];
Dir_Path(~[Dir_Path.isdir])=[];
ind = ismember({Dir_Path(:).name},{'compiled_mats','sig_stability','mic_template.mat','bouts.mat','bout_motif_indexes.mat','syntax_analysis'});
Dir_Path(ind)=[];
end

function [File_Check_Table,All_Neccessary_Exists]=Check_Syntax_Files(ID,Work_Dir)
%Return a 3 dimensional cell object and complete indicator, where first
%table is names(string), second is variables(string), third is if file
%needs to be remade(logical)
%name                   var                                         Replace?
%mic_template           mic
%cluster_index          Cluster_Index
%syntax_clustered       Clust_Select, Missed_Motif,...
%                       Motif_Cluster_Index,...
%                       Motifs_Anno, Total_Motif_Anno, Loud_Index
%Syntax_Summary         none


File_Check_Table=cell(4,1,5);
%1 File name
File_Check_Table{1,1,1}=fullfile(Work_Dir,"..","mic_template.mat");
File_Check_Table{2,1,1}=fullfile(Work_Dir,"syntax_analysis","Cluster_Index.mat");
File_Check_Table{3,1,1}=fullfile(Work_Dir,"syntax_analysis","Syntax_Clustered.mat");
File_Check_Table{4,1,1}=fullfile(Work_Dir,"syntax_analysis",ID+"_Motif_Syntax_Summary.svg");

%2 File exists
for I=1:4
    File_Check_Table{I,1,2}=exist(File_Check_Table{I,1,1},"file")==2;
end

%3 Variables
for I=1:3
    try
        File_Check_Table{I,1,3}=whos('-file',File_Check_Table{I,1,1});
    catch
        File_Check_Table{I,1,3}=struct('name',{''});
    end
end

%4 Has Variables
try
File_Check_Table{1,1,4}=all(contains([convertCharsToStrings({File_Check_Table{1,1,3}.name})],["Motif_Template","FS_TS","MIC_Time_Bins"]));
catch
    File_Check_Table{1,1,4}=0;
end
try
File_Check_Table{2,1,4}=all(contains([convertCharsToStrings({File_Check_Table{2,1,3}.name})],"Cluster_Index"));
catch
    File_Check_Table{2,1,4}=0;
end
try
File_Check_Table{3,1,4}=all(contains([convertCharsToStrings({File_Check_Table{3,1,3}.name})],["Cluster_Select","Missed_Motif","Motif_Cluster_Index","Motifs_Anno","Total_Motif_Anno","Loud_Index"]));
catch
    File_Check_Table{2,1,4}=0;
end
%5 Create File?
for I=1:3
    File_Check_Table{I,1,5}=File_Check_Table{I,1,2}&&File_Check_Table{I,1,4};
end
File_Check_Table{4,1,5}=File_Check_Table{4,1,2};

All_Neccessary_Exists=all([File_Check_Table{1:3,:,5}]);
end

function [mic,T] = Get_Mic_Template_V5(signal,FS)
while true
    close all
    [tmp, ~, T] = zftftb_pretty_sonogram(normalize(double(signal(:,1)), 'range'), ...
        FS, 'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);
    figure('pos',[200 200 1000 700])
    imagesc(tmp)
    title("Select mic template (draw on spectrogram)");
    title('After zooming, quit zoom then press ENTER')
    set(gca,'YDir','normal')
    % saveas(gcf,'../source_template.svg','svg')
    drawnow;
    disp("Select mic template (draw on spectrogram)");
    currkey=0;
    % do not move on until enter key is pressed
    while currkey~=1
        pause; % wait for a keypress
        currkey=get(gcf,'CurrentKey');
        if strcmp(currkey, 'return') % You also want to use strcmp here.
            currkey=1; % Error was here; the "==" should be "="
            rect = fix(getrect());
            ind = fix(FS*T(rect(1)):(FS*T(rect(1)+rect(3))));
            [micspec, ~, ~] = zftftb_pretty_sonogram(normalize(double(signal(ind)), 'range'), ...
                FS, 'len', 34, 'overlap', 33, 'clipping', [-3 2], 'filtering', 300);
            close all
        end
    end
    figure
    imagesc(micspec(end:-1:1, :));
    title("Good template? ")
    %if template des not look good, then redo
    if input("Good template? ")
        mic = signal(ind);
        break
    end
end
end