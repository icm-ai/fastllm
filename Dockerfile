# 使用NVIDIA CUDA 12.4作为基础镜像
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 AS builder

# 设置工作目录和环境变量  
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive  

# 安装必要的依赖，clone代码并编译，所有操作在一个RUN命令中完成
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    g++ \
    git \
    libnuma-dev \
    make \
    python3 \
    python3-pip \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # clone 并编译 fastllm
    && git clone --depth=1 https://github.com/ztxz16/fastllm.git \
    && cd fastllm \
    # 下面这行 CMAKE_CUDA_ARCHITECTURES 与 CUDA_ARCH 在此不能替换使用，可能是Cmake的bug，使用CUDA_ARCH即可
    && bash install.sh -DUSE_CUDA=ON -DUSE_NUMA=ON -DCUDA_ARCH=89 -DCMAKE_CUDA_COMPILER=$(which nvcc) \
    # Prepare source for tools setup by moving fastllm_pytools to tools/scripts/ftllm
    && mv /app/fastllm/tools/fastllm_pytools /app/fastllm/tools/scripts/ftllm \
    # Install ftllm command line tools
    && cd /app/fastllm/tools/scripts && python3 setup.py install \
    # 清理编译临时文件
    && cd /app/fastllm \
    && rm -rf build/CMakeFiles build/*.o

# 多阶段构建：创建最终镜像
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

# 设置工作目录和环境变量
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/app/fastllm/build/bin:${PATH}" \
    FASTLLM_CACHEDIR="/data"

# 安装运行时依赖并创建数据目录，所有操作在一个RUN命令中
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnuma1 \
    python3 \
    python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # 创建数据目录
    && mkdir -p /data \
    && chmod 777 /data

# 从构建阶段复制编译好的FastLLM，只复制必要文件
COPY --from=builder /app/fastllm /app/fastllm
COPY --from=builder /usr/local/lib/python3.10/dist-packages/ /usr/local/lib/python3.10/dist-packages/
COPY --from=builder /usr/local/bin/ftllm /usr/local/bin/ftllm
COPY --from=builder /usr/local/bin/streamlit /usr/local/bin/streamlit
RUN chmod +x /usr/local/bin/ftllm /usr/local/bin/streamlit

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python3 -c "import ftllm; print('fastllm health check passed')" || exit 1

# 容器启动时运行的命令  
CMD ["bash"]
