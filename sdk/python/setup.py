from setuptools import setup, find_packages

setup(
    name="beagle-client",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "requests>=2.31.0",
        "psycopg2-binary>=2.9.0",
    ],
    author="Demetrios Chiuratto",
    description="BEAGLE Python Client SDK",
    python_requires=">=3.8",
)


