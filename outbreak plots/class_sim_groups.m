
function [stats,graphdata,plotdata]=class_sim_groups(runstuff,params,protoc)

% how many days to run simulation
num_days=runstuff.maxDays;

hours_per_day=params.hour_per_day; % hours of class contact per day
is_asymp=params.is_asymp; % is index case aysmptomatic
cl_size=params.class_size; % students in class
frac_asymp=params.frac_asymp; % fraction of infecteds who are asymptomatic (never show symptoms)

beta_in=params.beta_base; % the basic beta, which is rate within groups
beta_out=beta_in*params.beta_aerosol_factor; % beta between groups

num_real_groups=params.num_real_groups; % how many group are there?

beta_index_factor=params.beta_index_factor; % how much more infecitious is index case
asymp_ratio=params.asymp_ratio; % how much less infectious are asymptomatics


daysDelay=protoc.days_delay; % how long from being tested to getting result 
tests_to_shutdown_group=protoc.tests_to_shutdown_group; %how many positive tests until you shut down a group
tests_to_shutdown_class=protoc.tests_to_shutdown_class; % how many group have to be shutdown until you shutdown the class (yes, name is inaccuarate)
num_control_groups=protoc.num_control_groups; % how many contact groups people think there are

was_infected=zeros(cl_size,1); % was person ever infected?
who_infected=zeros(cl_size,1); % then who infected them?

% is detected
was_symptomatic=zeros(cl_size,1);

% was disrupted
was_disrupted=zeros(cl_size,1);

diagnosis_delay=hours_per_day*daysDelay; % how long for diagnosis in hours

% build real groups
real_group=ceil(num_real_groups*(1:cl_size)/cl_size)';

% build control groups
control_group=ceil(num_control_groups*(1:cl_size)/cl_size)';
group_symp_count=zeros(num_control_groups,1);

huge=1e8; % big number to be infinity

% GROUP CONTROLS
% group_flag 1 if group is running, 0 if group is shut
group_flag=ones(num_control_groups,1);
% flag_set is zero until first symptoms appear
group_flag_set=zeros(num_control_groups,1); % enoug symptomatic case?
group_flag_time=huge*hours_per_day*ones(num_control_groups,1); % time to shut down class is not set yet

% CLASS CONTROLS
class_flag=1;  % class running?
class_flag_set=0; % sufficient groups shut down
class_flag_time=huge*hours_per_day;


% children matrix with infected or not S, E, I, symp, R
% keeps track of state of each child.
% also vectors that keep track of when students enter states
child_S=ones(cl_size,1);        % susceptible
child_E=zeros(cl_size,1); time_E=huge*hours_per_day*ones(cl_size,1);   % exposed
child_I=zeros(cl_size,1); time_I=huge*hours_per_day*ones(cl_size,1);   % infectious
child_symp=zeros(cl_size,1); time_symp=huge*hours_per_day*ones(cl_size,1); % symptomatic       
child_R=zeros(cl_size,1); time_R=huge*hours_per_day*ones(cl_size,1); % recovered

% this keeps track of what generation of infection child is
% -1 is not infected yet
child_generation=-1*ones(cl_size,1);

% set durations of time between getting it and being able to infect others
% mean is 3 days, std is 1 day, 6 hours per day
latentperiod=hours_per_day*mygamma(3,1,cl_size);
% dangerzone is now called PIP (presymptomatic infectious period)
dangerzone=hours_per_day*mygamma(params.mu_pip,0.5,cl_size);
% which students are asymptomatic
asymps=(rand(cl_size,1)<frac_asymp);
asymps(1)=is_asymp; % index case is determined

% modify so assymptotic fraction has dangerzone huge
dangerzone(asymps)=huge*hours_per_day;

% how long are people infectious for?
% mean 10, std 5
infectiousperiod=hours_per_day*mygamma(10,5,cl_size);


% intial infection
child_S(1,1)=0; child_I(1,1)=1; 
child_generation(1,1)=0;
time_E(1,1)=0; % skip exposure
time_I(1,1)=0;
was_infected(1,1)=1;
who_infected(1,1)=-1;

% time interval
delta_t=1; % units is hours
tottime=num_days*hours_per_day;
numsteps=round(tottime/delta_t);

% matrices where we store what state everyone is in at each time step
% initialize
S_mat=zeros(cl_size,numsteps+1);
E_mat=zeros(cl_size,numsteps+1);
I_mat=zeros(cl_size,numsteps+1);
symp_mat=zeros(cl_size,numsteps+1);
R_mat=zeros(cl_size,numsteps+1);
% initial state
S_mat(:,1)=child_S;
E_mat(:,1)=child_E;
I_mat(:,1)=child_I;
symp_mat(:,1)=child_symp;
R_mat(:,1)=child_R;

% for each time unit
for kk=1:numsteps
  
   currentTime=kk*delta_t;
         
   % are we running Monday to Friday or just Tuesday and Friday
   if ~params.TuesdayFriday
     class_running=~isweekend(currentTime,hours_per_day);
   else
     class_running=isTuesdayFriday(currentTime,hours_per_day);
   end
   
   % loop over all children to be infected
   for k=1:cl_size
       
    
      % loop over all children who might infect
     for jj=1:cl_size
        
         
       % generate random number- this will be used to determine if an
       % infection occurs
       % generating it for each pair of students every time step makes the
       % simulation have good properties. i.e. interventions that work on
       % average will also work for each simulation, etc.
       rand_num=rand;
             
       
       % is k susceptible, group is running, class is running 
       if (child_S(k,1)==1 && group_flag(control_group(k)) && class_flag && class_running) % if susceptible, maybe infect, if school is running      
            
                % is jj infectious
                if (child_I(jj,1)==1 && group_flag(control_group(jj)))
              % what should beta be based on same group, index case,
              % asymptomatic etc
                    if real_group(k)==real_group(jj)
                        beta=beta_in;
                    else
                        beta=beta_out;
                    end
                    if jj==1  % infectious child is index case
                        beta=beta*beta_index_factor;
                    end
                    if asymps(jj)
                        beta=beta*asymp_ratio;
                    end
              
                    % decide whether infection occurs
                    if rand_num<beta*delta_t
                        % update everything
                     child_S(k,1)=0;
                     child_E(k,1)=1;
                     time_E(k,1)=currentTime;
                     child_generation(k,1)=child_generation(jj,1)+1;
                     was_infected(k,1)=1;
                     who_infected(k,1)=jj;
                    end                
                end
           end
       end
       
     if child_E(k,1)==1 % if exposed, maybe turn infectious
           
       if currentTime > time_E(k,1)+ latentperiod(k,1) % past the latent period?
         child_E(k,1)=0; % no longer exposed
         child_I(k,1)=1; % now infectious
         time_I(k,1)=currentTime;
       end
     end
   
     if child_I(k,1)==1 % if infectious, maybe turn symptomatic
       if currentTime> time_I(k,1)+ dangerzone(k,1) % past the PIP?
         child_I(k,1)=0;
         child_symp(k,1)=1;           
         time_symp(k,1)=currentTime; 
         was_symptomatic(k,1)=1;
         was_disrupted(k,1)=1;
       end
     end
       
       
     if (child_I(k,1)==1 || child_symp(k,1)==1 ) % if infectious or symp might recover
       if currentTime> time_I(k,1)+ infectiousperiod(k,1) % are we past the infectious period
                child_I(k,1)=0;
                child_symp(k,1)=0;
                child_R(k,1)=1;
                time_R(k,1)=currentTime;
       end
     end
       
       
       
   end
   
   % compute tot symptomatic from each group
   for g=1:num_control_groups
       group_symp_count(g)=sum(child_symp(control_group==g));
   end
   
   
   % does a group get triggered?
   for g=1:num_control_groups
       if (group_symp_count(g)>=tests_to_shutdown_group && group_flag_set(g)==0)
           group_flag_time(g)=currentTime+diagnosis_delay;
           group_flag_set(g)=1;
           was_disrupted(control_group==g)=1;
       end
   end
   
    % do we shutdown a group?
   for g=1:num_control_groups
     if currentTime>=group_flag_time(g)
       group_flag(g)=0;
     end
   end
   
  
   
   % do we shutdown class?
   if (sum(~group_flag)>=tests_to_shutdown_class && ~class_flag_set)
       class_flag_set=1;
       class_flag=0;
       class_flag_time=currentTime;
       was_disrupted(:)=1;
   end
   
   S_mat(:,kk+1)=child_S;
   E_mat(:,kk+1)=child_E;
   I_mat(:,kk+1)=child_I;
   symp_mat(:,kk+1)=child_symp;
   R_mat(:,kk+1)=child_R;

   
end



tot_infected=sum(was_infected);
shutdowntime=class_flag_time/hours_per_day;

% for each person compute 1) total time assymptomatic 2) total time
% assymptomatic before shutdown of group or class
start_asymp=min([time_I tottime*ones(cl_size,1)],[],2);
end_asymp1=min([time_R time_symp tottime*ones(cl_size,1) ],[],2);
end_asymp2=min([time_R time_symp group_flag_time(control_group) tottime*ones(cl_size,1) class_flag_time*ones(cl_size,1)],[],2);
days_asymp1=(end_asymp1-start_asymp).*was_infected/hours_per_day;
days_asymp2=(end_asymp2-start_asymp).*was_infected/hours_per_day;
% fix to not have negative times
days_asymp1=days_asymp1.*(days_asymp1>0);
days_asymp2=days_asymp2.*(days_asymp2>0);


% store all the stats to return
stats.days_asymp_lax=sum(days_asymp1);
stats.days_asymp_strict=sum(days_asymp2);
stats.shutdowntime=shutdowntime;
stats.total_infected=tot_infected;
%stats.total_infected=total_infects(end);
stats.total_not_detected=sum(was_infected & ~was_symptomatic);
stats.groups_shut_down=num_control_groups-sum(group_flag);
stats.class_shut_down=1-class_flag;
stats.students_affected=max([stats.groups_shut_down*cl_size/num_control_groups stats.class_shut_down*cl_size]);
stats.students_disrupted=sum(was_disrupted);

graphdata.was_infected=was_infected;
graphdata.who_infected=who_infected;
graphdata.was_symptomatic=was_symptomatic;
graphdata.child_generation=child_generation;
graphdata.real_group=real_group;
graphdata.control_group=control_group;
graphdata.time_infected=time_E;
graphdata.time_symptomatic=time_symp;

plotdata.S=S_mat;
plotdata.E=E_mat;
plotdata.I=I_mat;
plotdata.symp=symp_mat;
plotdata.R=R_mat;
plotdata.timevect=(0:numsteps)*delta_t/hours_per_day;
plotdata.group_time=group_flag_time;
plotdata.real_group=real_group;
plotdata.class_time=class_flag_time;


end




