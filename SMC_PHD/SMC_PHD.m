classdef SMC_PHD < handle
% =====================================================================================>
% Properties:
%  - config: structure with the following parameters 
%            (Optional paramaters are marked with a (*))
%       
%       * Variables
%       -------------------
%       .type               = Type of PHD filter to use. (Currently only 'standard' and 'search' are implemented)
%                             -> 'standard' is equivalent to generic SMC PHD [1]
%                             -> 'search' is equivalent to [2], i.e. parameterised to detect, initialise and confirm targets
%       .Np                 = Number of particles
%       .particles          = Particles (n_x by Np matrix, n_x being the dimensionality of the state vector)
%       .w                  = Weights (1 by Np matrix)
%       .Pbirth (*)         = Probability of birth (Only required if .birth_strategy='mixture')
%       .Pdeath             = Probability of death (1-e_k|k-1 in [1])
%       .P_conf (*)         = Confirmation probability [2] (Only required if .type="search")
%       .NewTracks (*)      = List of tracks to be initiated [2] (Computed internally and only present if .type="search")
%       .PD                 = Probability of Detection 
%       .birth_strategy     = Stategy for generating birth particles. Options are: i) 'expansion'; ii) 'mixture'; iii) 'obs_oriented'
%       .J_k (*)            = Number of birth particles (Only required if .birth_strategy='expansion')
%       .z;                 = Measurements (n_y by Nm, Nm being the number of measurements)
%       .lambda;            = Clutter rate per unit volume (equivalent to ?_k(z) in [1] under the assumption of Poisson distributed clutter number)
%       .resample_strategy  = Resampling strategy. Set it either to 'multinomial_resampling' or 'systematic_resampling'
%       .k                  = Time index (k) or time since last iteration (Dt)
%                             (Depends on definition of .sys handle)
%       
%       * Function Handles
%       -------------------
%       .sys;               = Transition function (Dynamics)
%       .sys_noise;         = Dynamics noise generator function
%       .likelihood         = Likelihood pdf p(z|x)
%       .obs_model          = Observation model (without noise), used to project state (particles) in measurement space
%       .gen_x0             = Birth particle sampling function 
%                            (Assumed to have a single input parameter, which is the number of particles to be generated)
%       .gen_x1 (*)         = Birth particle sampling function around measurements (Only required if .birth_strategy='obs_oriented')
%                            (Assumed to have a single input parameter, which is the number of particles to be generated)
%
%       Author: Lyudmil Vladimirov, University of Liverpool
%
% [1]  B. N. Vo, S. Singh and A. Doucet, "Sequential Monte Carlo methods for multitarget filtering with random finite sets," in IEEE Transactions on Aerospace and Electronic Systems, vol. 41, no. 4, pp. 1224-1245, Oct. 2005.
% [2]  P. Horridge and S. Maskell,  �Using a probabilistic hypothesis density filter to confirm tracks in a multi-target environment,� in2011 Jahrestagung der Gesellschaft fr Informatik, October 2011.
% [3]  B. ngu Vo and S. Singh, �Sequential monte carlo implementation of the phd filter for multi-targettracking,� inIn Proceedings of the Sixth International Conference on Information Fusion, pp. 792�799, 2003.
% =====================================================================================>
    properties
        config
    end
    
    methods
        
        % Constructor function
        % --------------------
        function obj = SMC_PHD(prop)
            % Validate .type
            if ~isfield(prop,'type')
                fprintf('Type of PHD filter missing... Assuming "standard"..\n');
                prop.type = 'standard';
            end
            
            % Validate .Np
            if ~isfield(prop,'Np')
                fprintf('Number of particles missing... Assuming "Np = 1"..\n');
                prop.Np = 1;
            end
            
            % Validate .sys
            if ~isfield(prop,'sys')
                fprintf('Function handle to process equation missing... Assuming "sys = .(x)x"..\n');
                prop.sys = @(x) x;
            end
            
            % Validate .particles
            if (~isfield(prop,'particles'))
                fprintf('Particles not given... Proceeding to generation of initial particles..\n');
                if ~isfield(prop,'gen_x0')
                    fprintf('Function handle to sample from initial pdf not given... Cannot proceed..\n');
                    error('Please supply either an initial set of particles, or a function handle (gen_0) to allow for generation of initial ones!\n');
                else
                    prop.particles(:,:) = prop.gen_x0(prop.Np)'; % at time k=1
                    %end   
                    prop.w = repmat(1/prop.Np, prop.Np, 1);
                    fprintf('Generated %d particles with uniform weights\n',prop.Np);
                    prop.xhk(:,1) = sum(bsxfun(@times, prop.w(:,1)', prop.particles(:,:)),2);
                end
            else
                if size(prop.particles,2)~=prop.Np
                    error('Given number of particles (Np) is different that the size of supplied particle list! Aborting..\n');
                end
            end
            
            % Validate .w
            if ~isfield(prop,'w')
                fprintf('Initial set of weights not given... Proceeding to auto initialisation!\n');
                prop.w = repmat(1/prop.Np, prop.Np);
                fprintf('Uniform weights for %d particles have been created\n', prop.Np);
            else
                if (all(prop.w ==0))
                    fprintf('Initial set of weights given as all zeros... Proceeding to auto initialisation!\n');
                    prop.w = repmat(1/prop.Np, prop.Np);
                    fprintf('Uniform weights for %d particles have been created\n', prop.Np);
                end   
            end
            
            % Validate .z
            if ~isfield(prop,'z')
                fprintf('No initial observation supplied... Assuming "z = 0"\n');
                prop.z = 0;
            end
            
            % Validate .obs_model
            if ~isfield(prop,'obs_model')
                error('Function handle for observation model (obs_model) (without noise) has not been given... Aborting..\n');
            end
            
             % Validate .likelihood
            if ~isfield(prop,'likelihood')
                error('Function handle for likelihood model p(y|x)(likelihood) has not been given... Aborting..\n');
            end
            
            % Validate .sys_noise
            if ~isfield(prop,'sys_noise')
                error('Function handle to generate system noise (sys_noise) has not been given... Aborting..\n');
            end
            
            % Validate .resample_strategy
            if ~isfield(prop,'resampling_strategy')
                fprintf('Resampling strategy not given... Assuming "resampling_strategy = systematic_resampling"..\n');
                prop.resampling_strategy = 'systematic_resampling';
            end
            
            % Validate .k
            if (~isfield(prop,'k')|| prop.k<1)
                fprinf('Iterator (k) was not initialised properly... Setting "k = 1"..');
                prop.k = 1;
            end
            
            % Validate .birth_strategy
            if ~isfield(prop,'birth_strategy')
                fprintf('birth_strategy missing... Assumming birth_strategy = "expansion".\n');
                prop.birth_strategy = 'expansion';
            end
            
            % Validate .J_k
            if (strcmp(prop.birth_strategy,'expansion') && ~isfield(prop,'J_k'))
                error('Birth strategy is set to "expansion" but no number of birth particles (J_k) is supplied... Aborting...');
            end
            
            % Validate .Pbirth
            if (strcmp(prop.birth_strategy,'mixture') && ~isfield(prop,'Pbirth'))
                error('Birth strategy is set to "mixture" but no birth probability (P_birth) is supplied... Aborting...');
            end
            
            % Validate .Pdeath
            if ~isfield(prop,'Pdeath')
                fprintf('Probability Pdeath missing... Assumming Pdeath = 0.005.\n');
                prop.Pdeath = 0.005;
            end
            
            % Validate .PD
            if ~isfield(prop,'PD')
                fprintf('Probability PD missing... Assumming PD = 0.9.\n');
                prop.PD = 0.9;
            end
            
            % Validate P_conf
            if ~isfield(prop,'P_conf')
                fprintf('Probability P_conf missing... Assumming P_conf = 0.9.\n');
                prop.P_conf = 0.9;
            end
            obj.config = prop;
      
        end
        
        % Predict function
        % ----------------
        % Performs the relevant SMC PHD prediction algo, based on the selected .type
        function [config] = Predict(obj)
            switch obj.config.type
                case 'standard' % [1]
                    config = obj.Predict_Standard();
                case 'search' % [2]
                    config = obj.Predict_Search();
            end
        end
        
        % Update function
        % ----------------
        % Performs the relevant SMC PHD update algo, based on the selected .type
        function [config] = Update(obj)
            switch obj.config.type
                case 'standard' % [1]
                    config = obj.Update_Standard();
                case 'search' % [2]
                    config = obj.Update_Search();
            end
        end
        
        % Predict_Standard function
        % ----------------
        % Performs the "standard" prediction step, as dictated by [1]
        function [config] = Predict_Standard(obj)
            
            % Create local copy of config
            config = obj.config;
            
            % Propagate old (k-1) particles and generate new birth particles
            if(strcmp(config.birth_strategy, 'expansion')) 
                % Expansion method is equivalent to Eqs. (25-26) of [1]
                % assuming that:
                %  -> e_k|k-1(?) = 1-Pdeath
                %  -> b_k|k-1(x|?) = 0 (No spawned targets)
                %  -> q_k(x_k|x_k-1,Z_k) = f_k|k-1(x|?)  
                %  i.e. (25) = (1-Pdeath)*w_k-1^i
                % and
                %  -> ?_k(x_k) = 0.2*p_k(x_k|Z_k)
                %  i.e  (26) = 0.2/J_k
            
                % Expand number of particles to accomodate for births
                config.particles = [config.particles, zeros(size(config.particles, 1), config.J_k)]; 
                config.w = [config.w, zeros(1, config.J_k)];
                config.Np_total = config.Np + config.J_k;  

                % Generate Np normally predicted particles
                config.particles(:,1:config.Np) = config.sys(config.k, config.particles(:,1:config.Np), config.sys_noise(config.Np)); % Simply propagate all particles
                config.w(:,1:config.Np) = (1-config.Pdeath)* config.w(:,1:config.Np);

                % Generate birth particles 
                config.particles(:,config.Np+1:end) = config.gen_x0(config.J_k)';
                config.w(:,config.Np+1:end) = 0.2/config.J_k;
                
            elseif(strcmp(config.birth_strategy, 'mixture'))
                % Mixture method is equivalent to the one proposed in Section 5 of [2]
                
                % Compute mixture components
                a = config.Pbirth;
                b = (1-config.Pdeath);
                Np_n = binornd(config.Np,b/(a+b)); % Number of normally predicted particles
                Np_b = config.Np - Np_n; % Number of birth particles

                % Generate normally predicted particles 
                if(Np_n)
                    config.particles(:,1:Np_n) = config.sys(config.k, config.particles(:,1:Np_n), config.sys_noise(Np_n)); % Simply propagate all particles
                end

                % Generate birth particles 
                if(Np_b>0)
                    config.particles(:,Np_n+1:end) = config.gen_x0(Np_b)';
                end
                config.w(:, Np_n+1:end) = 0.2/(config.Np-Np_n); % Assign weights to birth particles
                
                config.Np_total = config.Np;
                
            elseif(strcmp(config.birth_strategy, 'obs_oriented'))
                % =========================================================>
                % UNDER DEVELOPMENT: Still in beta version. Not recommended
                % =========================================================>
                config.J_k = size(config.z,2)*100; % 100 particles are assigned per measurement
                
                % Expand number of particles to accomodate for births
                config.particles = [config.particles, zeros(4, config.J_k)]; 
                config.w = [config.w, zeros(1, config.J_k)];
                config.Np_total = config.Np + config.J_k;  

                % Generate Np normally predicted particles
                config.particles(:,1:config.Np) = config.sys(config.k, config.particles(:,1:config.Np), config.sys_noise(config.Np)); % Simply propagate all particles
                config.w(:,1:config.Np) = (1-config.Pdeath)* config.w(:,1:config.Np);

                % Generate birth particles 
                for i=1:size(config.z,2)
                    config.particles(:,config.Np+1+(i-1)*100:config.Np+(i-1)*100+100) = config.gen_x0(config.z(:,i), 100)';
                end
                %config.particles(:,config.Np+1:end) = config.gen_x0(config.J_k)';
                config.w(:,config.Np+1:end) = 0.2/config.J_k;
            else
                error('Birth strategy "%s" not defined', config.birth_strategy); 
            end
            
            % reassing config
            obj.config = config;
        end
        
        % Update_Standard function
        % ----------------
        % Performs the "standard" update step, as dictated by [1]
        function [config] = Update_Standard(obj)
            
            % Create local copy of config
            config = obj.config;
            
            % Tranform particles to measurement space
            trans_particles = config.obs_model(config.particles); 
            
            % Compute g(z|x) matrix as in [1] 
            config.g = zeros(size(trans_particles,2),size(config.z, 2));
            for i = 1:size(config.z, 2)
                config.g(:,i) = config.likelihood(config.k, trans_particles, config.z(:,i));
            end
            
            % Compute C_k(z) Eq. (27) of [1]  
            C_k = zeros(1,size(config.z,2));
            for i = 1:size(config.z,2)   % for all measurements
                C_k(i) = sum(config.PD*config.g(:,i)'.*config.w,2);
            end
            config.C_k = C_k;
            
            % Update weights Eq. (28) of [1]
            config.w = (1-config.PD + sum(config.PD*config.g./(ones(config.Np_total,1)*(config.lambda+config.C_k)),2))'.*config.w;
            
            % Resample (equivalent to Step 3 of [1]
            config.N_k = sum(config.w,2); % Compute total mass
            [config.particles, config.w] = obj.resample(config.particles, (config.w/config.N_k)', config.resampling_strategy, config.Np); % Resample
            config.w = config.w'*config.N_k; % Rescale
            
            % reassing config
            obj.config = config;
        end
        
        % Predict_Search function
        % ----------------
        % Performs the "search" prediction step, as dictated by [2]
        function [config] = Predict_Search(obj)
            
            % Create local copy of config
            config = obj.config;
            
            % Propagate old (k-1) particles and generate new birth particles
            if(strcmp(config.birth_strategy, 'expansion'))
                % Expansion method is equivalent to Eqs. (25-26) of [1]
                % assuming that:
                %  -> e_k|k-1(?) = (1-Pdeath)
                %  -> b_k|k-1(x|?) = 0
                %  -> ?_k|k-1 = q_k 
                %  i.e. (25) = (1-Pdeath)*w_k-1^i
                % and
                %  -> ?_k = 0.2*p_k(\tilde{x}_k^i|Z_k)
                %  i.e  (26) = 1/J_k
                
                % Expand number of particles to accomodate for births
                config.particles = [config.particles, zeros(4, config.J_k)]; 
                config.w = [config.w, zeros(1, config.J_k)];
                config.Np_total = config.Np + config.J_k;  

                % Generate Np normally predicted particles
                config.particles(:,1:config.Np) = config.sys(config.k, config.particles(:,1:config.Np), config.sys_noise(config.Np)); % Simply propagate all particles
                config.w(:,1:config.Np) = (1-config.Pdeath)* config.w(:,1:config.Np);

                % Generate birth particles 
                config.particles(:,config.Np+1:end) = config.gen_x0(config.J_k)';
                config.w(:,config.Np+1:end) = 0.2/config.J_k;
                
            elseif(strcmp(config.birth_strategy, 'mixture'))
                % Mixture method is equivalent to the one proposed in Section 5 of [2]
                
                % Compute mixture components
                a = config.Pbirth;
                b = (1-config.Pdeath);
                Np_n = binornd(config.Np,b/(a+b)); % Number of normally predicted particles
                Np_b = config.Np - Np_n; % Number of birth particles

                % Generate normally predicted particles 
                if(Np_n)
                    config.particles(:,1:Np_n) = config.sys(config.k, config.particles(:,1:Np_n), config.sys_noise(Np_n)); % Simply propagate all particles
                end

                % Generate birth particles 
                if(Np_b>0)
                    config.particles(:,Np_n+1:end) = config.gen_x0(Np_b)';
                end
                config.w(:, Np_n+1:end) = 0.2/(config.Np-Np_n); % Assign weights to birth particles
                config.Np_total = config.Np;
                
            elseif(strcmp(config.birth_strategy, 'obs_oriented'))
                % =========================================================>
                % UNDER DEVELOPMENT: Still in beta version. Not recommended
                % =========================================================>
                config.J_k2 = size(config.z,2)*10; % 10 particles are assigned per measurement
                config.Np_total = config.Np + config.J_k + config.J_k2; 
                
                % Expand number of particles to accomodate for births
                config.particles = [config.particles, zeros(4,  config.J_k + config.J_k2)]; 
                config.w = [config.w, zeros(1,  config.J_k + config.J_k2)]; 

                % Generate Np normally predicted particles
                config.particles(:,1:config.Np) = config.sys(config.k, config.particles(:,1:config.Np), config.sys_noise(config.Np)); % Simply propagate all particles
                config.w(:,1:config.Np) = (1-config.Pdeath)* config.w(:,1:config.Np);

                % Generate birth particles 
                for i=1:size(config.z,2)
                    config.particles(:,config.Np+1+(i-1)*10:config.Np+(i-1)*10+10) = config.gen_x1(config.z(:,i), 10)';
                end
                %config.particles(:,config.Np+1:end) = config.gen_x0(config.J_k)';
                config.w(:,config.Np+1:config.Np+config.J_k2) = 0.2/(config.J_k+config.J_k2);
                
                % Generate birth particles 
                config.particles(:,config.Np+config.J_k2+1:end) = config.gen_x0(config.J_k)';
                config.w(:,config.Np+1:end) = 0.2/(config.J_k+config.J_k2);
            else
                error('Birth strategy "%s" not defined.. Choose between "expansion" or "mixture" strategies!', config.birth_strategy); 
            end
            
            % reassing config
            obj.config = config;
            
        end
        
        % Update_Search function
        % ----------------
        % Performs the "search" update step, as dictated by [2]
        function [config] = Update_Search(obj)
            
            % Create local copy of config
            config = obj.config;
            
            % Tranform particles to measurement space
            trans_particles = config.obs_model(config.particles(:,:)); 
            
            % Get rhi measurement weights (computed externally as in Eq. (16) in [2])
            config.rhi = config.rhi==1; %ones(1,size(config.z,2)); % Assume all measurements are unused
            
            % Perform particle gating
            % =========================================================>
            % UNDER DEVELOPMENT: Still in beta version. Not recommended
            % =========================================================>
            %DistM = ones(config.Np_total, size(config.z, 2))*1000;
            %for i = 1:size(config.z, 2)
            %    DistM(:,i) = mahalDist(trans_particles', config.z(:,i), config.R, 2);
            %    valid_particles(:,i) = DistM(:,i)<10;
            %end
            % % Compute g(z|x) matrix as in [1] 
            %config.g = zeros(size(trans_particles,2),size(config.z, 2));
            %for i = 1:size(config.z, 2)
            %    config.g(find(valid_particles(:,i)),i) = config.likelihood(config.k, trans_particles(1:2,find(valid_particles(:,i)))', config.z(:,i)');
            %end
            
            % Compute g(z|x) matrix as in [1] 
            config.g = zeros(size(trans_particles,2),size(config.z, 2));
            for i = 1:size(config.z, 2)
                config.g(:,i) = config.likelihood(config.k, trans_particles(1:2,:)', config.z(:,i)');
            end

            % Compute C_k(z) Eq. (27) of [1]  
            C_k = zeros(1,size(config.z,2));
            for i = 1:size(config.z,2)   % for all measurements
                C_k(i) = sum(config.PD*config.rhi(i)*config.g(:,i)'.*config.w,2);
            end
            config.C_k = C_k;

            % Calculate pi Eq. (21) of [2]
            config.pi = zeros(1, size(config.z,2));
            for j = 1:size(config.z,2)
                config.pi(j) = sum((config.PD*config.rhi(j)*config.g(:,j)'/(config.lambda+config.C_k(j))).*config.w,2);
            end
            %config.pi = sum(config.PD*repmat(config.rhi,config.Np_total,1).*config.g./(ones(config.Np_total,1)*(config.lambda+config.C_k)).*(ones(size(config.z, 2),1)*config.w)',1);
            
            % Update weights Eq. (28) of [1]
            w = zeros(size(config.z,2)+1, config.Np_total);
            w(1,:) = (1-config.PD)*config.w;
            for j = 1:size(config.z,2)
                w(j+1,:) = (config.PD*config.rhi(j)*config.g(:,j)'/(config.lambda+config.C_k(j))).*config.w; 
            end
            %w(2:end,:) = (config.PD*repmat(config.pi,config.Np_total,1).*config.g./repmat(config.lambda+config.C_k,config.Np_total,1))'.*repmat(config.w,size(config.pi,2),1);
            
            
            % Select measurements to be used for spawning new tracks
            CritMeasurements = find(config.pi>config.P_conf);
            config.NewTracks = [];
            
            % Initiate new tracks
            for j = 1:size(CritMeasurements,2)
                MeasInd = CritMeasurements(j); % Index of measurement
                
                % Get particles and weights
                NewTrack.particles = config.particles;
                NewTrack.w         = w(MeasInd+1,:);
                % Resample particles to ensure they are correctly localised
                % around the measurement
                N_k = sum(NewTrack.w,2);
                [NewTrack.particles, NewTrack.w] = obj.resample(NewTrack.particles, (NewTrack.w/N_k)', config.resampling_strategy, config.Np_conf);
                NewTrack.ExistProb = config.pi(MeasInd);
                config.NewTracks{end+1} = NewTrack; 
            end
            
            % Select measurements which are not to be used for new tracks
            NonCritMeasurements = setdiff([1:size(config.z, 2)], CritMeasurements);
            
            % Rescale new particle weights, considering only non critical measurements
            config.w = sum(w([1,NonCritMeasurements+1],:),1);
            %config.w = (1-config.PD + sum(config.PD*config.g./(ones(config.Np_total,1)*(config.lambda+config.C_k)),2))'.*config.w;
            
            % Resample (equivalent to Step 3 of [1]
            config.N_k = sum(config.w,2); % Compute total mass
            [config.particles, config.w] = obj.resample(config.particles, (config.w/config.N_k)', config.resampling_strategy, config.Np);
            config.w = config.w'*config.N_k; % Rescale
            
            % reassing config
            obj.config = config;
        end
        
       % Resampling function
       % -------------------
        function [xk, wk, idx] = resample(obj, xk, wk, resampling_strategy, Np_new)
            Np = length(wk);  % Np = number of particles
            switch resampling_strategy
               case 'multinomial_resampling'
                  with_replacement = true;
                  idx = randsample(1:Np, Np_new, with_replacement, wk);
                %{
                  THIS IS EQUIVALENT TO:
                  edges = min([0 cumsum(wk)'],1); % protect against accumulated round-off
                  edges(end) = 1;                 % get the upper edge exact
                  % this works like the inverse of the empirical distribution and returns
                  % the interval where the sample is to be found
                  [~, idx] = histc(sort(rand(Np,1)), edges);
                %}
               case 'systematic_resampling'
                  % this is performing latin hypercube sampling on wk
                  edges = min([0 cumsum(wk)'],1); % protect against accumulated round-off
                  edges(end) = 1;                 % get the upper edge exact
                  u1 = rand/Np_new;
                  % this works like the inverse of the empirical distribution and returns
                  % the interval where the sample is to be found
                  [~, ~, idx] = histcounts(u1:1/Np_new:1, edges);
               otherwise
                  error('Resampling strategy not implemented\n')
            end
            xk = xk(:,idx);                    % extract new particles
            wk = repmat(1/Np_new, 1, Np_new)';          % now all particles have the same weight
        end
    end
end