classdef KalmanFilterX < matlab.mixin.Copyable % Handle class with copy functionality
    % KalmanFilterX class
    %
    % Summary of KalmanFilterX:
    % This is a class implementation of a vanilla Kalman Filter.
    %
    % KalmanFilterX Properties:
    %    - config   = structure with fields:
    %       .k          = time index. Can also act as a time interval (Dt), depending on the underlying models. 
    %       .x (*)      = Estimated state mean (x_{k|k}) - (nx x 1) column vector, where nx is the dimensionality of the state
    %       .P (*)      = Estimated state covariance (P_{k|k}) - (nx x nx) matrix 
    %       .x_pred     = Predicted state mean (x_{k|k-1}) - (nx x 1) column vector
    %       .P_pred     = Predicted state mean (P_{k|k-1}) - (nx x nx) matrix
    %       .y          = Measurement (y_k) - (ny x 1) column vector, where ny is the dimensionality of the measurement
    %       .y_Pred     = Predicted measurement mean (H*x_{k|k-1}) - (ny x 1) column vector
    %       .S          = Innovation covariance (S_k) - (ny x ny) column vector
    %       .K          = Kalman Gain (K_k) - (nx x ny) column vector
    %   
    %   - dyn_model (*)       = Object handle to Dynamic Model Class
    %   - obs_model (*)   = Object handle to Observation Model Class
    %
    %   (*) Signifies properties necessary to instantiate a class object
    %
    % KalmanFilterX Methods:
    %    KalmanFilterX  - Constructor method
    %    Predict        - Performs KF prediction step
    %    Update         - Performs KF update step
    %    Iterate        - Performs a complete KF iteration (Predict & Update)
    %    Smooth         - Performs KF smoothing on a provided set of estimates
    % 
    % KalmanFilterX Example:
    %     N = 500; % Simulate 500 seconds/iterations
    % 
    %     % Constant Velocity Model
    %     config_cv.dim = 2;
    %     config_cv.q = 0.1;
    %     CVmodel = ConstantVelocityModel(config_cv);
    % 
    %     % Positional Observation Model
    %     config_meas.dim = 2;
    %     config_meas.r = 5;
    %     obs_model = PositionalObsModel(config_meas);
    % 
    %     % Set initial true target state
    %     s = zeros(config_cv.dim*2,N);
    %     s(:,1) = [0; 0; 0.1; 0.3]; % (Position target at 0,0 with velocity of 1 m/s on each axis
    % 
    %     % Initiate Kalman Filter
    %     config_kf.k = 1;  % Use k as 1 sec Dt interval for CV model
    %     config_kf.x = s(:,1); 
    %     config_kf.P = CVmodel.config.Q(1);
    %     kf = KalmanFilterX(config_kf, CVmodel, obs_model);
    % 
    %     % Containers
    %     filtered_estimates = cell(1,N);
    % 
    % 
    %     % START OF SIMULATION
    %     % ===================>
    %     for k = 1:N
    % 
    %         % Generate new state and measurement
    %         if(k~=1)
    %             s(:,k) = CVmodel.propagate_parts(s(:,k-1));
    %         end
    %         y(:,k) = obs_model.sample_from(obs_model.transform_mean(s(:,k)));
    % 
    %         % Iterate Kalman Filter
    %         kf.config.y = y(:,k);
    %         kf.predict(); 
    %         kf.update();
    % 
    %         % Store filtered estimates
    %         filtered_estimates{k} = kf.config;
    %     end
    %     % END OF SIMULATION
    %     % ===================>
    % 
    %     % Compute smoothed estimates
    %     smoothed_estimates = kf.Smooth(filtered_estimates);
    % 
    %     % Extract estimates
    %     x_filtered = zeros(config_cv.dim*2,N);
    %     x_smoothed = zeros(config_cv.dim*2,N);
    %     for k = 1:N
    %         x_filtered(:,k) = filtered_estimates{k}.x;
    %         x_smoothed(:,k) = smoothed_estimates{k}.x;
    %     end
    % 
    %     figure
    %     plot(s(1,:),s(2,:),'.-k', x_filtered(1,:), x_filtered(2,:), 'o-b', x_smoothed(1,:), x_smoothed(2,:), 'x-r');
    
     properties
        config
        dyn_model
        obs_model
    end
    methods
        function obj = KalmanFilterX(config, dyn_model, obs_model)
        % KalmanFilterX - Constructor method
        %   
        %   Inputs:
        %       config           |
        %       dyn_model      | => Check class help for more details
        %       obs_model |
        %   
        %   Usage:
        %       kf = KalmanFilterX(config, dyn_model, obs_model); 
        %
        %   See also Predict, Update, Iterate, Smooth.
        
            % Validate config
            if ~isfield(config,'k'); disp('[KF] No initial time index/interval provided.. Setting "k=1"...'); config.k = 1; end
            %if ~isfield(config,'x'); error('[KF] Initial state mean missing!'); end
            %if ~isfield(config,'P'); error('[KF] Initial state covariance missing!'); end
            if ~isfield(config,'y'); disp('[KF] No initial set of observations provided.. Setting "y=[]"...'); config.y = []; end
            if ~isfield(config,'u'); disp('[KF] No control input supplied provided.. Setting "u=0"...'); config.u=0; end
            if ~isfield(config,'B'); disp('[KF] No control input gain supplied provided.. Setting "B=0"...'); config.B=0; end
            obj.config = config;
            
            % Validate dyn_model
            if ~isobject(dyn_model); error('[KF] No dynamic model object provided!'); end
            obj.dyn_model = dyn_model;
            
            % Validate obs_model
            if ~isobject(obs_model); error('[KF] No observation model object provided!'); end
            obj.obs_model = obs_model;
        end
        
        function Predict(obj)
        % Predict - Performs KF prediction step
        %   
        %   Inputs:
        %       N/A 
        %   (NOTE: The time index/interval "obj.config.k" needs to be updated, when necessary, before calling this method) 
        %   
        %   Usage:
        %       (kf.config.k = 1; % 1 sec)
        %       kf.Predict();
        %
        %   See also KalmanFilterX, Update, Iterate, Smooth.
            
            % Compute predicted state mean and covariance
            % obj.config.x_pred = obj.dyn_model.config.f(obj.config.k) * obj.config.x + obj.config.B * obj.config.u;
            % obj.config.P_pred = obj.dyn_model.config.f(obj.config.k) * obj.config.P * obj.dyn_model.config.f(obj.config.k)' +  obj.dyn_model.config.Q(obj.config.k);
            % 
            % % Compute predicted measurement mean and covariance
            % obj.config.y_pred = obj.obs_model.config.h(obj.config.k) * obj.config.x_pred;
            % obj.config.S      = obj.obs_model.config.h(obj.config.k) * obj.config.P_pred * obj.obs_model.config.H(obj.config.k)' + obj.obs_model.config.R;
            
            % ALTERNATIVE METHOD (making use of model specific functions)
            % ===========================================================>
            % Compute predicted state mean and covariance
            obj.config.x_pred = obj.dyn_model.sys(obj.config.k, obj.config.x) + obj.config.B * obj.config.u;
            obj.config.P_pred = obj.dyn_model.sys_cov(obj.config.k, obj.config.P);
            
            % Compute predicted measurement mean and covariance
            obj.config.y_pred  = obj.obs_model.obs(obj.config.k, obj.config.x_pred);
            obj.config.S       = obj.obs_model.obs_cov(obj.config.k, obj.config.P_pred);
            
        end
        
        
        function Update(obj)
        % Update - Performs KF update step
        %   
        %   Inputs:
        %       N/A 
        %   (NOTE: The measurement "obj.config.y" needs to be updated, when necessary, before calling this method) 
        %   
        %   Usage:
        %       (kf.config.y = y_new; % y_new is the new measurement)
        %       kf.Update(); 
        %
        %   See also KalmanFilterX, Predict, Iterate, Smooth.
        
            if(size(obj.config.y,2)>1)
                error('[KF] More than one measurement have been provided for update. Use KalmanFilterX.UpdateMulti() function instead!');
            elseif size(obj.config.y,2)==0
                warning('[KF] No measurements have been supplied to update track! Skipping Update step...');
                return;
            end
        
            % Compute Kalman gain
            obj.config.K = obj.config.P_pred * obj.obs_model.config.h(obj.config.k)' / (obj.config.S);

            % Compute filtered estimates
            obj.config.x = obj.config.x_pred + obj.config.K * (obj.config.y - obj.config.y_pred);
            obj.config.P = obj.config.P_pred - obj.config.K * obj.obs_model.config.h(obj.config.k) * obj.config.P_pred;
        end
        
        function UpdateMulti(obj, assocWeights)
        % UpdateMulti - Performs KF update step, for multiple measurements
        %   
        %   Inputs:
        %       assoc_weights: a (1 x Nm+1) association weights matrix. The first index corresponds to the dummy measurement and
        %                       indices (2:Nm+1) correspond to measurements. Default = [0, ones(1,ObsNum)/ObsNum];
        %       LikelihoodMatrix: a (Nm x Np) likelihood matrix, where Nm is the number of measurements and Np is the number of particles.
        %
        %   (NOTE: The measurement "obj.config.y" needs to be updated, when necessary, before calling this method) 
        %   
        %   Usage:
        %       (pf.config.y = y_new; % y_new is the new measurement)
        %       pf.Update(); 
        %
        %   See also ParticleFilterX, Predict, Iterate, Smooth, resample.
            ObsNum = size(obj.config.y,2);  
            ObsDim = size(obj.config.y,1); 
            
            if(~ObsNum)
                warning('[KF] No measurements have been supplied to update track! Skipping Update step...');
                obj.config.x = obj.config.x_pred;
                obj.config.P = obj.config.P_pred;
                return;
            end
            
            if(~exist('assocWeights','var'))
                warning('[KF] No association weights have been supplied to update track! Applying default "assocWeights = [0, ones(1,ObsNum)/ObsNum];"...');
                assocWeights = [0, ones(1,ObsNum)/ObsNum]; % (1 x Nm+1)
            end
            
            % Compute Kalman gain
            innov_err      = obj.config.y - obj.config.y_pred(:,ones(1,ObsNum)); % error (innovation) for each sample
            obj.config.K   = obj.config.P_pred*obj.obs_model.config.h(obj.config.k)'/obj.config.S;  

            % update
            %Pc              = (eye(size(obj.config.x,1)) - obj.config.K*obj.obs_model.config.h(obj.config.k))*obj.config.P_pred;
            Pc              = obj.config.P_pred - obj.config.K*obj.config.S*obj.config.K';
            tot_innov_err   = innov_err*assocWeights(2:end)';
            Pgag            = obj.config.K*((innov_err.*assocWeights(ones(ObsDim,1),2:end))*innov_err' - tot_innov_err*tot_innov_err')*obj.config.K';
            
            obj.config.x    = obj.config.x_pred + obj.config.K*tot_innov_err;  
            obj.config.P    = assocWeights(1)*obj.config.P_pred + (1-assocWeights(1))*Pc + Pgag;
        end
        
        function Iterate(obj)
        % Iterate - Performs a complete KF iteration (Predict & Update)
        %   
        %   Inputs:
        %       N/A 
        %   (NOTE: The time index/interval "obj.config.k" and measurement "obj.config.y" need to be updated, when necessary, before calling this method) 
        %   
        %   Usage:
        %       (kf.config.k = 1; % 1 sec)
        %       (kf.config.y = y_new; % y_new is the new measurement)
        %       kf.Iterate();
        %
        %   See also KalmanFilterX, Predict, Update, Smooth.
        
            obj.Predict();  % Predict         
            obj.Update();   % Update
        end
        
        function smoothed_estimates = Smooth(obj, filtered_estimates)
        % Smooth - Performs KF smoothing on a provided set of estimates
        %   
        %   Inputs:
        %       filtered_estimates: a (1 x N) cell array, where N is the total filter iterations and each cell is a copy of obj.config after each iteration
        %                            
        %   (NOTE: The filtered_estimates array can be computed by running "filtered_estimates{k} = kf.config" after each iteration of the filter recursion) 
        %   
        %   Usage:
        %       kf.Smooth(filtered_estimates);
        %
        %   See also KalmanFilterX, Predict, Update, Iterate.
        
            % Allocate memory
            N                           = length(filtered_estimates);
            smoothed_estimates          = cell(1,N);
            smoothed_estimates{N}       = filtered_estimates{N}; 
            
            % Perform Rauch�Tung�Striebel Backward Recursion
            for k = N-1:-1:1
                smoothed_estimates{k}.C     = filtered_estimates{k}.P * obj.dyn_model.config.F(filtered_estimates{k+1}.k)' / filtered_estimates{k+1}.P_pred;
                smoothed_estimates{k}.x     = filtered_estimates{k}.x + smoothed_estimates{k}.C * (smoothed_estimates{k+1}.x - filtered_estimates{k+1}.x_pred);
                smoothed_estimates{k}.P     = filtered_estimates{k}.P + smoothed_estimates{k}.C * (smoothed_estimates{k+1}.P - filtered_estimates{k+1}.P_pred) * smoothed_estimates{k}.C';                            
            end
        end
            
    end
end