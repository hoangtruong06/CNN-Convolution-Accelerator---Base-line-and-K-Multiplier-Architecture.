import numpy as np
import matplotlib.pyplot as plt
import torch
from torchvision import datasets, transforms

def conv2d(input_map, kernel):
    """
    Task A: 2D convolution from scratch using nested loops.
    input_map: H x W array
    kernel: K x K array
    returns: (H-K+1) x (W-K+1) array
    """
    H, W = input_map.shape
    K, _ = kernel.shape
    out_h = H - K + 1
    out_w = W - K + 1

    output_map = np.zeros((out_h, out_w))

    for r in range(out_h):
        for c in range(out_w):
            # Extract the KxK patch
            patch = input_map[r:r+K, c:c+K]
            # Element-wise multiply and sum
            output_map[r, c] = np.sum(patch * kernel)

    return output_map

# Verification with hand-computable example from specification
input_test = np.array([
    [1, 2, 3, 0, 1, 2],
    [0, 1, 2, 3, 0, 1],
    [1, 0, 1, 2, 3, 0],
    [2, 1, 0, 1, 2, 3],
    [0, 1, 2, 0, 1, 2],
    [1, 0, 1, 1, 0, 1]
])
kernel_test = np.array([
    [1, 0, -1],
    [1, 0, -1],
    [1, 0, -1]
])

result = conv2d(input_test, kernel_test)
print("Test Output[0][0]:", result[0, 0], "(Expected: -4.0)")