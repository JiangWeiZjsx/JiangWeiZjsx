# 编程基础环境

## Anaconda 环境配置

## Docker 环境配置
* 编译 dockerfile 文件
```bash
docker build -t a1-pytorch .
```

* 备份 docker 安装后文件
```bash
docker save -o phd-latex-backup.tar phd-latex:latest
```

* 运行 docker 容器（带GPU）
```bash
docker run --gpus all -it -v ${PWD}:/app --name my_research a1-pytorch:latest bash
```

- 上传本地仓库到 docker hub:

```bash
docker tag a1-pytorch:latest johnwing/a1pytorch:tagname
docker push johnwing/a1pytorch:tagname
```

# 编码工具

# 编码规范
