/**
 * Copyright 1993-2015 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

/**
 * This sample implements bitonic sort and odd-even merge sort, algorithms
 * belonging to the class of sorting networks.
 * While generally subefficient on large sequences
 * compared to algorithms with better asymptotic algorithmic complexity
 * (i.e. merge sort or radix sort), may be the algorithms of choice for sorting
 * batches of short- or mid-sized arrays.
 * Refer to the excellent tutorial by H. W. Lang:
 * http://www.iti.fh-flensburg.de/lang/algorithmen/sortieren/networks/indexen.htm
 *
 * Victor Podlozhnyuk, 07/09/2009
 */


 //compile with:
 // nvcc -Iinc -m64 -arch=sm_35 bitonicsortmain.cu -o bitonicsortmain
 // nvcc  bitonicsortmain.cu -Iinc -o bitonicsortmain


// CUDA Runtime
#include <cuda_runtime.h>

// Utilities and system includes
#include <helper_cuda.h>
#include <helper_timer.h>

// #include "sortingNetworks_common.h"

#include "bitonicSort.cu"
#include "sortingNetworks_validate.cpp"

#define SIZE 1<<10
// #define BATCH SIZE
// #define BATCH (16<<20)/16
// #define BATCH (16<<20)/512
// #define BATCH (16<<20)/2048

////////////////////////////////////////////////////////////////////////////////
// Test driver
////////////////////////////////////////////////////////////////////////////////
int main(int argc, char **argv)
{
    cudaError_t error;
    printf("%s Starting...\n\n", argv[0]);

    printf("Starting up CUDA context...\n");
    // int dev = findCudaDevice(argc, (const char **)argv);

    cudaSetDevice (0);
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    
    uint *h_InputKey, *h_InputVal, *h_OutputKeyGPU, *h_OutputValGPU;
    uint *d_InputKey, *d_InputVal,    *d_OutputKey,    *d_OutputVal;
    // StopWatchInterface *hTimer = NULL;

    const uint             N = SIZE;
    const uint           DIR = 0;
    const uint     numValues = SIZE;
    const uint numIterations = 1;

    printf("Allocating and initializing host arrays...\n\n");
    // sdkCreateTimer(&hTimer);
    h_InputKey     = (uint *)malloc(N * sizeof(uint));
    h_InputVal     = (uint *)malloc(N * sizeof(uint));
    h_OutputKeyGPU = (uint *)malloc(N * sizeof(uint));
    h_OutputValGPU = (uint *)malloc(N * sizeof(uint));
    srand(2001);

    for (uint i = 0; i < N; i++)
    {
        h_InputKey[i] = rand() % numValues;
        h_InputVal[i] = i;
    }

    printf("Allocating and initializing CUDA arrays...\n\n");
    error = cudaMalloc((void **)&d_InputKey,  N * sizeof(uint));
    checkCudaErrors(error);
    error = cudaMalloc((void **)&d_InputVal,  N * sizeof(uint));
    checkCudaErrors(error);
    error = cudaMalloc((void **)&d_OutputKey, N * sizeof(uint));
    checkCudaErrors(error);
    error = cudaMalloc((void **)&d_OutputVal, N * sizeof(uint));
    checkCudaErrors(error);
    error = cudaMemcpy(d_InputKey, h_InputKey, N * sizeof(uint), cudaMemcpyHostToDevice);
    checkCudaErrors(error);
    error = cudaMemcpy(d_InputVal, h_InputVal, N * sizeof(uint), cudaMemcpyHostToDevice);
    checkCudaErrors(error);

    int flag = 1;
    printf("Running GPU bitonic sort (%u identical iterations)...\n\n", numIterations);

    uint arrayLength = SIZE;
    
    printf("Testing array length %u (%u arrays per batch)...\n", arrayLength, N / arrayLength);
  

    // sdkResetTimer(&hTimer);
    // sdkStartTimer(&hTimer); 
    uint threadCount = 0;

    float elapsedTime;
    error = cudaDeviceSynchronize();
    checkCudaErrors(error);
    cudaEventRecord(start, 0);

    for (uint i = 0; i < numIterations; i++)
        threadCount = bitonicSort(
                            d_OutputKey,
                            d_OutputVal,
                            d_InputKey,
                            d_InputVal,
                            N / arrayLength,
                            arrayLength,
                            DIR
                        );



    error = cudaDeviceSynchronize();
    checkCudaErrors(error);

    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsedTime, start, stop);

    // sdkStopTimer(&hTimer);
    // printf("Average time: %f ms\n\n", sdkGetTimerValue(&hTimer) / numIterations);

    printf("Processing time: %f (ms)\n", elapsedTime);
  
    double dTimeSecs = 1.0e-3 * elapsedTime / numIterations;
    printf("sortingNetworks-bitonic, Throughput = %.4f MElements/s, Time = %.5f s, Size = %u elements, NumDevsUsed = %u, Workgroup = %u\n",
            (1.0e-6 * (double)arrayLength/dTimeSecs), dTimeSecs, arrayLength, 1, threadCount);
    

    printf("\nValidating the results...\n");
    printf("...reading back GPU results\n");
    error = cudaMemcpy(h_OutputKeyGPU, d_OutputKey, N * sizeof(uint), cudaMemcpyDeviceToHost);
    checkCudaErrors(error);
    error = cudaMemcpy(h_OutputValGPU, d_OutputVal, N * sizeof(uint), cudaMemcpyDeviceToHost);
    checkCudaErrors(error);

    int keysFlag = validateSortedKeys(h_OutputKeyGPU, h_InputKey, N / arrayLength, arrayLength, numValues, DIR);
    int valuesFlag = validateValues(h_OutputKeyGPU, h_OutputValGPU, h_InputKey, N / arrayLength, arrayLength);
    flag = flag && keysFlag && valuesFlag;

    // printf("\n");
    // printf("flag is %d\n", flag);

    // printf("Shutting down...\n");
    
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    // sdkDeleteTimer(&hTimer);
    cudaFree(d_OutputVal);
    cudaFree(d_OutputKey);
    cudaFree(d_InputVal);
    cudaFree(d_InputKey);
    free(h_OutputValGPU);
    free(h_OutputKeyGPU);
    free(h_InputVal);
    free(h_InputKey);

    exit(flag ? EXIT_SUCCESS : EXIT_FAILURE);
}
