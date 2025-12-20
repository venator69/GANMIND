function main_gan_full()

%% ========================= CONFIG =========================
config.INPUT_FOLDER = "cat_images";
config.OUTPUT_FOLDER = "dataset_processed";
config.THRESH = 140;

config.EPOCHS = 50;
config.BATCH = 256;
config.LATENT = 64;

config.CRITIC_ITERS = 5;
config.LAMBDA_LP = 10;

%% ===================== GPU CHECK ==========================
if canUseGPU
    gpuDevice(1);
    disp("GPU ENABLED!");
else
    disp("WARNING: CPU MODE (slow)");
end

%% ===================== PREPROCESS =========================
disp("=== PREPROCESS DATASET ===");

needProcess = true;
if exist(config.OUTPUT_FOLDER,'dir')
    files = dir(fullfile(config.OUTPUT_FOLDER,"*.png"));
    if ~isempty(files)
        disp("Dataset processed exists → SKIP preprocessing");
        needProcess = false;
    end
end

if needProcess
    disp("Processing dataset...");
    if ~exist(config.OUTPUT_FOLDER,'dir')
        mkdir(config.OUTPUT_FOLDER);
    end

    files = dir(fullfile(config.INPUT_FOLDER,"*.png"));
    for i = 1:length(files)
        img = imread(fullfile(config.INPUT_FOLDER,files(i).name));

        if size(img,3)==3
            img = rgb2gray(img);
        end

        img = imresize(img,[28 28]);

        img(img < config.THRESH) = 0;
        img(img >= config.THRESH) = 255;

        imwrite(img, fullfile(config.OUTPUT_FOLDER,files(i).name));

        if mod(i,50)==0
            fprintf("Processed %d/%d\n",i,length(files));
        end
    end
    disp("Preprocessing Done!");
end

%% ===================== LOAD DATASET =======================
ds = imageDatastore(config.OUTPUT_FOLDER);
imgs = readall(ds);
N = length(imgs);

dataset = zeros(N,784,'single');

for i = 1:N
    x = single(imgs{i}) ./ 255;
    x = x*2 - 1;
    dataset(i,:) = reshape(x,1,[]);
end

if canUseGPU, dataset = gpuArray(dataset); end

fprintf("Loaded dataset: %d images (flattened 784)\n",N);

%% ================== BUILD NETWORKS ========================
disp("Building WGAN-LP Networks...");

G = generatorNet(config.LATENT);
C = criticNet();

G = dlnetwork(G);
C = dlnetwork(C);

%% ================= OPTIMIZER STATES =======================
tg=[]; tgsq=[];
tc=[]; tcsq=[];
iteration = 0;

%% ================= TRAINING LOOP ==========================
disp("=== TRAINING START (WGAN-LP) ===");

lossG_hist=[];
lossC_hist=[];

for epoch = 1:config.EPOCHS
    
    perm = randperm(N);
    data = dataset(perm,:);
    
    for i = 1:config.BATCH:N
        
        real = data(i:min(i+config.BATCH-1,end),:);
        real = dlarray(real','CB');   % (784,Batch)

        %% ========== CRITIC UPDATE ==========
        for k = 1:config.CRITIC_ITERS
            z = randn(config.LATENT,size(real,2),'single');
            if canUseGPU, z = gpuArray(z); end
            z = dlarray(z,'CB');

            [gradC,lossC] = dlfeval(@criticGradients,C,G,real,z,config);
            iteration = iteration+1;

            [C,tc,tcsq] = adamupdate(C,gradC,tc,tcsq, ...
                iteration,1e-4,0.5,0.9);
        end

        %% ========== GENERATOR UPDATE ==========
        z = randn(config.LATENT,size(real,2),'single');
        if canUseGPU, z = gpuArray(z); end
        z = dlarray(z,'CB');

        [gradG,lossG] = dlfeval(@generatorGradients,C,G,z);
        iteration = iteration+1;

        [G,tg,tgsq] = adamupdate(G,gradG,tg,tgsq, ...
            iteration,1e-4,0.5,0.9);
    end
    
    lossG_hist(end+1)=gather(extractdata(lossG));
    lossC_hist(end+1)=gather(extractdata(lossC));

    fprintf("Epoch %d/%d | Critic=%.4f | Gen=%.4f\n", ...
        epoch,config.EPOCHS,lossC_hist(end),lossG_hist(end));

    if mod(epoch,10)==0
        preview(G,config.LATENT,epoch);
    end
end

disp("=== TRAINING COMPLETE ===");

%% ========= LOSS PLOT =========
figure;
plot(lossG_hist,'LineWidth',2); hold on;
plot(lossC_hist,'LineWidth',2);
legend("Generator","Critic");
xlabel("Epoch");
ylabel("Loss");
grid on;
title("WGAN-LP Training Loss");

%% ========= EXPORT WEIGHTS Q6.10 =========
disp("Exporting weights Q6.10...");
exportNetworkQ610(G,"G");
exportNetworkQ610(C,"C");
disp("Export complete.");

end

%% ================= GENERATOR ==============================
function lgraph = generatorNet(latent)
lgraph = layerGraph([
    featureInputLayer(latent,"Normalization","none")
    fullyConnectedLayer(256)
    reluLayer
    fullyConnectedLayer(256)
    reluLayer
    fullyConnectedLayer(784)
    tanhLayer
]);
end

%% ================= CRITIC (NO SIGMOID) ====================
function lgraph = criticNet()
lgraph = layerGraph([
    featureInputLayer(784,"Normalization","none")
    fullyConnectedLayer(256)
    leakyReluLayer(0.2)
    fullyConnectedLayer(256)
    leakyReluLayer(0.2)
    fullyConnectedLayer(256)
    leakyReluLayer(0.2)
    fullyConnectedLayer(1)
]);
end

%% ================= CRITIC GRAD ============================
function [grad,lossC] = criticGradients(C,G,real,z,config)
fake = forward(G,z);
sr = forward(C,real);
sf = forward(C,fake);
wasserstein = -(mean(sr)-mean(sf));
lp = lipschitzPenalty(C,real,fake,config.LAMBDA_LP);
lossC = wasserstein + lp;
grad = dlgradient(lossC,C.Learnables);
end

%% ================= GENERATOR GRAD =========================
function [grad,lossG] = generatorGradients(C,G,z)
fake = forward(G,z);
sf = forward(C,fake);
lossG = -mean(sf);
grad = dlgradient(lossG,G.Learnables);
end

%% ================= LIPSCHITZ PENALTY ======================
function lp = lipschitzPenalty(C,real,fake,lambda)
alpha = rand(1,size(real,2),'single');
alpha = reshape(alpha,1,[]);
interp = alpha.*real + (1-alpha).*fake;
d = forward(C,interp);
g = dlgradient(sum(d,'all'),interp);
norms = sqrt(sum(g.^2,1));
lp = lambda * mean(max(norms-1,0).^2);
end

%% ================= PREVIEW ================================
function preview(G,latent,epoch)
z = randn(latent,9,'single');
if canUseGPU, z=gpuArray(z); end
z = dlarray(z,'CB');
imgs = extractdata(forward(G,z));
imgs = gather(imgs);
imgs = reshape(imgs,28,28,[]);
figure;
montage((imgs+1)/2,"Size",[3 3]);
title("Preview Epoch " + epoch);
drawnow;
end

%% ================= EXPORT Q6.10 ===========================
function exportNetworkQ610(net,prefix)

learn = net.Learnables;

for i = 1:size(learn,1)

    lname = learn.Layer(i);
    pname = learn.Parameter(i);

    V = gather(extractdata(learn.Value{i}));

    q = round(V * 2^10);
    q = max(min(q,32767),-32768);

    if pname=="Weights"
        fname = sprintf("%s_%s_weight_q610.hex",prefix,lname);
    else
        fname = sprintf("%s_%s_bias_q610.hex",prefix,lname);
    end

    fid = fopen(fname,"w");
    for k = 1:numel(q)
        v = int16(q(k));
        fprintf(fid,"%04X\n", typecast(v,'uint16'));
    end
    fclose(fid);

    fprintf("Exported %s (%s)\n",string(lname),string(pname));
end
end
