import configparser
import os
import tarfile
import tempfile
from subprocess import check_call
from typing import Optional


LIBS = ["cyclecloud_api-8.0.1-py2.py3-none-any.whl", "cyclecloud-scalelib-0.1.1.tar.gz", "cyclecloud-gridengine-2.0.0.tar.gz"]


def execute() -> None:
    parser = configparser.ConfigParser()
    ini_path = os.path.abspath("project.ini")

    with open(ini_path) as fr:
        parser.read_file(fr)

    version = parser.get("project", "version")
    if not version:
        raise RuntimeError("Missing [project] -> version in {}".format(ini_path))

    if not os.path.exists("dist"):
        os.makedirs("dist")

    tf = tarfile.TarFile.gzopen("dist/cyclecloud-gridengine-pkg-{}.tar.gz".format(version), "w")

    build_dir = tempfile.mkdtemp("cyclecloud-gridengine")

    def _add(name: str, path: Optional[str] = None, mode: Optional[int] = None) -> None:
        path = path or name
        tarinfo = tarfile.TarInfo("cyclecloud-gridengine/" + name)
        tarinfo.size = os.path.getsize(path)
        tarinfo.mtime = os.path.getmtime(path)
        if mode:
            tarinfo.mode = mode

        with open(path, "rb") as fr:
            tf.addfile(tarinfo, fr)

    for dep in LIBS:
        dep_path = os.path.abspath(os.path.join("libs", dep))
        _add("packages/" + dep, dep_path)
        check_call(["pip", "download", dep_path], cwd=build_dir)
    
    print("Using build dir", build_dir)
    for fil in os.listdir(build_dir):
        if fil.startswith("certifi-2019"):
            print("WARNING: Ignoring duplicate certifi {}".format(fil))
            continue
        path = os.path.join(build_dir, fil)
        _add("packages/" + fil, path)

    _add("install.sh", mode=os.stat("install.sh")[0])


if __name__ == "__main__":
    execute()
