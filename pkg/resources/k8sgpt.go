/*
Copyright 2023 The K8sGPT Authors.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package resources

import (
	"context"
	err "errors"
	"fmt"

	v1 "k8s.io/api/rbac/v1"

	"github.com/k8sgpt-ai/k8sgpt-operator/api/v1alpha1"
	"github.com/k8sgpt-ai/k8sgpt-operator/pkg/utils"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/retry"
	"k8s.io/utils/ptr"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

// SyncOrDestroy enum create or destroy
type SyncOrDestroy int

const (
	SyncOp SyncOrDestroy = iota
	DestroyOp
)

func addSecretAsEnvToDeployment(secretName string, secretKey string,
	config v1alpha1.K8sGPT, c client.Client,
	deployment *appsv1.Deployment) error {
	secret := &corev1.Secret{}
	er := c.Get(context.Background(), types.NamespacedName{Name: secretName,
		Namespace: config.Namespace}, secret)
	if er != nil {
		return err.New("secret does not exist, cannot add to env of deployment")
	}
	envVar := corev1.EnvVar{
		Name: secretKey,
		ValueFrom: &corev1.EnvVarSource{
			SecretKeyRef: &corev1.SecretKeySelector{
				LocalObjectReference: corev1.LocalObjectReference{
					Name: secretName,
				},
				Key: secretKey,
			},
		},
	}
	deployment.Spec.Template.Spec.Containers[0].Env = append(
		deployment.Spec.Template.Spec.Containers[0].Env, envVar,
	)
	return nil
}

// GetServiceAccount Create ServiceAccount for K8sGPT
func GetServiceAccount(config v1alpha1.K8sGPT, serviceAccountName string) (*corev1.ServiceAccount, error) {
	serviceAccount := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      serviceAccountName,
			Namespace: config.Namespace,
			OwnerReferences: []metav1.OwnerReference{
				{
					Kind:               config.Kind,
					Name:               config.Name,
					UID:                config.UID,
					APIVersion:         config.APIVersion,
					BlockOwnerDeletion: utils.PtrBool(true),
					Controller:         utils.PtrBool(true),
				},
			},
			Annotations: make(map[string]string),
		},
	}

	if config.Spec.ExtraOptions != nil {
		if config.Spec.ExtraOptions.ServiceAccountIRSA != "" {
			serviceAccount.ObjectMeta.Annotations["eks.amazonaws.com/role-arn"] = config.Spec.ExtraOptions.ServiceAccountIRSA
		}
	}

	return serviceAccount, nil
}

// GetService Create service for K8sGPT
func GetService(config v1alpha1.K8sGPT) (*corev1.Service, error) {
	// Create service
	service := corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      config.Name,
			Namespace: config.Namespace,
			OwnerReferences: []metav1.OwnerReference{
				{
					Kind:               config.Kind,
					Name:               config.Name,
					UID:                config.UID,
					APIVersion:         config.APIVersion,
					BlockOwnerDeletion: utils.PtrBool(true),
					Controller:         utils.PtrBool(true),
				},
			},
		},
		Spec: corev1.ServiceSpec{
			Selector: map[string]string{
				"app": config.Name,
			},
			Ports: []corev1.ServicePort{
				{
					Port: 8080,
				},
			},
		},
	}

	return &service, nil
}

func GetClusterRoleBinding(config v1alpha1.K8sGPT, serviceAccountName string,
	crbName string, clusterRoleName string) (*v1.ClusterRoleBinding, error) {
	clusterRoleBinding := &v1.ClusterRoleBinding{
		ObjectMeta: metav1.ObjectMeta{
			Name: crbName,
			OwnerReferences: []metav1.OwnerReference{
				{
					Kind:               config.Kind,
					Name:               config.Name,
					UID:                config.UID,
					APIVersion:         config.APIVersion,
					BlockOwnerDeletion: utils.PtrBool(true),
					Controller:         utils.PtrBool(true),
				},
			},
		},
		Subjects: []v1.Subject{
			{
				Kind:      "ServiceAccount",
				Name:      serviceAccountName,
				Namespace: config.Namespace,
			},
		},
		RoleRef: v1.RoleRef{
			Kind: "ClusterRole",
			Name: clusterRoleName,
		},
	}
	return clusterRoleBinding, nil
}

// GetClusterRole Create ClusterRole for K8sGPT
func GetClusterRole(config v1alpha1.K8sGPT, serviceAccountName string) (*v1.ClusterRole, error) {
	clusterRole := &v1.ClusterRole{
		ObjectMeta: metav1.ObjectMeta{
			Name: fmt.Sprintf("%s-clusterrole", serviceAccountName),
			OwnerReferences: []metav1.OwnerReference{
				{
					Kind:               config.Kind,
					Name:               config.Name,
					UID:                config.UID,
					APIVersion:         config.APIVersion,
					BlockOwnerDeletion: utils.PtrBool(true),
					Controller:         utils.PtrBool(true),
				},
			},
		},
		Rules: []v1.PolicyRule{
			{
				APIGroups: []string{""},
				Resources: []string{"pods", "services", "secrets", "endpoints", "nodes", "configmaps", "namespaces"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{""},
				Resources: []string{"persistentvolumeclaims"},
				Verbs:     []string{"list"},
			},
			{
				APIGroups: []string{""},
				Resources: []string{"events"},
				Verbs:     []string{"list"},
			},
			{
				APIGroups: []string{"apps"},
				Resources: []string{"deployments", "replicasets", "statefulsets", "daemonsets", "replicationcontrollers"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"batch"},
				Resources: []string{"cronjobs", "jobs"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"autoscaling"},
				Resources: []string{"horizontalpodautoscalers"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"networking.k8s.io"},
				Resources: []string{"ingresses", "networkpolicies"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"admissionregistration.k8s.io"},
				Resources: []string{"validatingwebhookconfigurations", "mutatingwebhookconfigurations"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"policy"},
				Resources: []string{"poddisruptionbudgets"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"storage.k8s.io"},
				Resources: []string{"storageclasses"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{"gateway.networking.k8s.io"},
				Resources: []string{"gatewayclasses", "gateways", "httproutes"},
				Verbs:     []string{"get", "list", "watch"},
			},
			{
				APIGroups: []string{""},
				Resources: []string{"pods/log"},
				Verbs:     []string{"get", "list", "watch"},
			},
		},
	}
	return clusterRole, nil
}

// GetDeployment Create deployment with the latest K8sGPT image
func GetDeployment(config v1alpha1.K8sGPT, outOfClusterMode bool, c client.Client,
	serviceAccountName string) (*appsv1.Deployment, error) {

	// Create deployment
	image := config.Spec.Repository + ":" + config.Spec.Version
	replicas := int32(1)
	deployment := appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      config.Name,
			Namespace: config.Namespace,
			OwnerReferences: []metav1.OwnerReference{
				{
					Kind:               config.Kind,
					Name:               config.Name,
					UID:                config.UID,
					APIVersion:         config.APIVersion,
					BlockOwnerDeletion: utils.PtrBool(true),
					Controller:         utils.PtrBool(true),
				},
			},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"app": config.Name,
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"app": config.Name,
					},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName: serviceAccountName,
					Containers: []corev1.Container{
						{
							Name:            "k8sgpt",
							ImagePullPolicy: config.Spec.ImagePullPolicy,
							Image:           image,
							Args: []string{
								"serve",
							},
							Env: []corev1.EnvVar{
								{
									Name:  "K8SGPT_MODEL",
									Value: config.Spec.AI.Model,
								},
								{
									Name:  "K8SGPT_BACKEND",
									Value: config.Spec.AI.Backend,
								},
								{
									Name:  "K8SGPT_MAX_TOKENS",
									Value: config.Spec.AI.MaxTokens,
								},
								{
									Name:  "K8SGPT_TOP_K",
									Value: config.Spec.AI.Topk,
								},
								{
									Name:  "XDG_CONFIG_HOME",
									Value: "/k8sgpt-data/.config",
								},
								{
									Name:  "XDG_CACHE_HOME",
									Value: "/k8sgpt-data/.cache",
								},
							},
							Ports: []corev1.ContainerPort{
								{
									ContainerPort: 8080,
								},
							},
							Resources: corev1.ResourceRequirements{
								Limits: corev1.ResourceList{
									corev1.ResourceCPU: func() resource.Quantity {
										if config.Spec.Resources != nil {
											if config.Spec.Resources.Limits != nil {
												if cpuLimit, exists := config.Spec.Resources.Limits["cpu"]; exists {
													return cpuLimit
												}
											}
										}
										return resource.MustParse("1")
									}(),
									corev1.ResourceMemory: func() resource.Quantity {
										if config.Spec.Resources != nil {
											if config.Spec.Resources.Limits != nil {
												if memLimit, exists := config.Spec.Resources.Limits["memory"]; exists {
													return memLimit
												}
											}
										}
										return resource.MustParse("512Mi")
									}(),
								},
								Requests: corev1.ResourceList{
									corev1.ResourceCPU: func() resource.Quantity {
										if config.Spec.Resources != nil {
											if config.Spec.Resources.Requests != nil {
												if cpuRequest, exists := config.Spec.Resources.Requests["cpu"]; exists {
													return cpuRequest
												}
											}
										}
										return resource.MustParse("0.2")
									}(),
									corev1.ResourceMemory: func() resource.Quantity {
										if config.Spec.Resources != nil {
											if config.Spec.Resources.Requests != nil {
												if memRequest, exists := config.Spec.Resources.Requests["memory"]; exists {
													return memRequest
												}
											}
										}
										return resource.MustParse("256Mi")
									}(),
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									MountPath: "/k8sgpt-data",
									Name:      "k8sgpt-vol",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}},
							Name:         "k8sgpt-vol",
						},
					},
					NodeSelector: config.Spec.NodeSelector,
				},
			},
		},
	}
	if outOfClusterMode {
		// Keep the service account if using Amazon Bedrock with IRSA
		needsServiceAccount := config.Spec.AI.Backend == v1alpha1.AmazonBedrock &&
			config.Spec.ExtraOptions != nil &&
			config.Spec.ExtraOptions.ServiceAccountIRSA != ""

		if !needsServiceAccount {
			// No need of ServiceAccount since the Deployment will use
			// a kubeconfig pointing to an external cluster.
			deployment.Spec.Template.Spec.ServiceAccountName = ""
			deployment.Spec.Template.Spec.AutomountServiceAccountToken = ptr.To(false)
		}

		kubeconfigPath := fmt.Sprintf("/tmp/%s", config.Name)

		deployment.Spec.Template.Spec.Containers[0].Args = append(deployment.Spec.Template.Spec.Containers[0].Args, fmt.Sprintf("--kubeconfig=%s/kubeconfig", kubeconfigPath))
		deployment.Spec.Template.Spec.Containers[0].VolumeMounts = append(deployment.Spec.Template.Spec.Containers[0].VolumeMounts, corev1.VolumeMount{
			Name:      "kubeconfig",
			ReadOnly:  true,
			MountPath: kubeconfigPath,
		})
		deployment.Spec.Template.Spec.Volumes = append(deployment.Spec.Template.Spec.Volumes, corev1.Volume{
			Name: "kubeconfig",
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: config.Spec.Kubeconfig.Name,
					Items: []corev1.KeyToPath{
						{
							Key:  config.Spec.Kubeconfig.Key,
							Path: "kubeconfig",
						},
					},
				},
			},
		})
	}
	// This check is necessary for the simple OpenAI journey, let's keep it here and guard from breaking other types of backend
	if config.Spec.AI.Secret != nil && config.Spec.AI.Backend != v1alpha1.AmazonBedrock {
		password := corev1.EnvVar{
			Name: "K8SGPT_PASSWORD",
			ValueFrom: &corev1.EnvVarSource{
				SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{
						Name: config.Spec.AI.Secret.Name,
					},
					Key: config.Spec.AI.Secret.Key,
				},
			},
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, password,
		)
	}
	if config.Spec.RemoteCache != nil {

		// check to see if key/value exists
		addRemoteCacheEnvVar := func(name, key string) {
			envVar := corev1.EnvVar{
				Name: name,
				ValueFrom: &corev1.EnvVarSource{
					SecretKeyRef: &corev1.SecretKeySelector{
						LocalObjectReference: corev1.LocalObjectReference{
							Name: config.Spec.RemoteCache.Credentials.Name,
						},
						Key: key,
					},
				},
			}
			deployment.Spec.Template.Spec.Containers[0].Env = append(
				deployment.Spec.Template.Spec.Containers[0].Env, envVar,
			)
		}
		if config.Spec.RemoteCache.Azure != nil {
			addRemoteCacheEnvVar("AZURE_CLIENT_ID", "azure_client_id")
			addRemoteCacheEnvVar("AZURE_TENANT_ID", "azure_tenant_id")
			addRemoteCacheEnvVar("AZURE_CLIENT_SECRET", "azure_client_secret")
		} else if config.Spec.RemoteCache.S3 != nil {
			addRemoteCacheEnvVar("AWS_ACCESS_KEY_ID", "aws_access_key_id")
			addRemoteCacheEnvVar("AWS_SECRET_ACCESS_KEY", "aws_secret_access_key")
		}
	}

	// Add provider ID if in ai spec
	if config.Spec.AI.ProviderId != "" {
		providerId := corev1.EnvVar{
			Name:  "K8SGPT_PROVIDER_ID",
			Value: config.Spec.AI.ProviderId,
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, providerId,
		)
	}

	if config.Spec.AI.BaseUrl != "" {
		baseUrl := corev1.EnvVar{
			Name:  "K8SGPT_BASEURL",
			Value: config.Spec.AI.BaseUrl,
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, baseUrl,
		)
	}

	// Configure the k8sgpt deployment resource if required
	if config.Spec.Resources != nil {
		deployment.Spec.Template.Spec.Containers[0].Resources = *config.Spec.Resources
	}
	// Engine is required only when azureopenai is the ai backend
	if config.Spec.AI.Engine != "" && config.Spec.AI.Backend == v1alpha1.AzureOpenAI {
		engine := corev1.EnvVar{
			Name:  "K8SGPT_ENGINE",
			Value: config.Spec.AI.Engine,
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, engine,
		)
	} else if config.Spec.AI.Engine != "" && config.Spec.AI.Backend != v1alpha1.AzureOpenAI {
		return &appsv1.Deployment{}, err.New("engine is supported only by azureopenai provider")
	}

	// Configure ProxyEndpoint env variable
	if config.Spec.AI.ProxyEndpoint != "" {
		proxyEndpoint := corev1.EnvVar{
			Name:  "K8SGPT_PROXY_ENDPOINT",
			Value: config.Spec.AI.ProxyEndpoint,
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, proxyEndpoint,
		)
	}

	// Add checks for amazonbedrock
	if config.Spec.AI.Backend == v1alpha1.AmazonBedrock {
		if config.Spec.AI.Secret != nil {
			if err := addSecretAsEnvToDeployment(config.Spec.AI.Secret.Name, "AWS_ACCESS_KEY_ID", config, c, &deployment); err != nil {
				return &appsv1.Deployment{}, err
			}
			if err := addSecretAsEnvToDeployment(config.Spec.AI.Secret.Name, "AWS_SECRET_ACCESS_KEY", config, c, &deployment); err != nil {
				return &appsv1.Deployment{}, err
			}
		}
		if config.Spec.AI.Region == "" {
			return &appsv1.Deployment{}, err.New("default region is required for amazonbedrock backend")
		}
		deployment.Spec.Template.Spec.Containers[0].Env = append(
			deployment.Spec.Template.Spec.Containers[0].Env, corev1.EnvVar{
				Name:  "AWS_DEFAULT_REGION",
				Value: config.Spec.AI.Region,
			},
		)
	}
	// Add checks for ibmwatsonxai
	if config.Spec.AI.Backend == v1alpha1.IBMWatsonxAI {
		if config.Spec.AI.Secret != nil {
			if err := addSecretAsEnvToDeployment(config.Spec.AI.Secret.Name, "K8SGPT_PROVIDER_ID", config, c, &deployment); err != nil {
				return &appsv1.Deployment{}, err
			}
		}
	}
	return &deployment, nil
}

func Sync(ctx context.Context, c client.Client,
	config v1alpha1.K8sGPT, i SyncOrDestroy) error {

	var objs []client.Object
	outOfClusterMode := config.Spec.Kubeconfig != nil
	// Build the names for the sa,cr,crd
	serviceAccountName := fmt.Sprintf("k8sgpt-%s", config.Namespace)
	clusterRoleName := fmt.Sprintf("%s-clusterrole", serviceAccountName)
	clusterRoleNameBinding := fmt.Sprintf("%s-binding", clusterRoleName)

	sa, er := GetServiceAccount(config, serviceAccountName)
	if er != nil {
		return er
	}

	objs = append(objs, sa)

	svc, er := GetService(config)
	if er != nil {
		return er
	}

	objs = append(objs, svc)

	deployment, er := GetDeployment(config, outOfClusterMode, c, serviceAccountName)
	if er != nil {
		return er
	}

	objs = append(objs, deployment)

	clusterRole, er := GetClusterRole(config, serviceAccountName)
	if er != nil {
		return er
	}

	objs = append(objs, clusterRole)

	clusterRoleBinding, err := GetClusterRoleBinding(config, serviceAccountName, clusterRoleNameBinding, clusterRoleName)
	if err != nil {
		return err
	}
	objs = append(objs, clusterRoleBinding)

	// for each object, create or destroy
	for _, obj := range objs {
		switch i {
		case SyncOp:

			// before creation, we will check to see if the secret exists if used as a ref
			if config.Spec.AI.Secret != nil {

				secret := &corev1.Secret{}
				er := c.Get(ctx, types.NamespacedName{Name: config.Spec.AI.Secret.Name,
					Namespace: config.Namespace}, secret)
				if er != nil {
					return er
				}
			}

			err := doSync(ctx, c, obj)
			if err != nil {
				// If the object already exists, ignore the error
				if !errors.IsAlreadyExists(err) {
					return err
				}
			}
		case DestroyOp:
			err := c.Delete(ctx, obj)
			if err != nil {
				// if the object is not found, ignore the error
				if !errors.IsNotFound(err) {
					return err
				}
			}
		}
	}

	return nil
}

func doSync(ctx context.Context, clt client.Client, obj client.Object) error {
	var mutateFn controllerutil.MutateFn
	switch expect := obj.(type) {
	case *appsv1.Deployment:
		exist := &appsv1.Deployment{}
		err := clt.Get(context.Background(), client.ObjectKeyFromObject(obj), exist)
		if err != nil && !errors.IsNotFound(err) {
			return err
		} else if err == nil {
			mutateFn = func() error {
				exist.Spec = expect.Spec
				return nil
			}
			obj = exist
		}
	case *corev1.Service:
		exist := &corev1.Service{}
		err := clt.Get(context.Background(), client.ObjectKeyFromObject(obj), exist)
		if err != nil && !errors.IsNotFound(err) {
			return err
		} else if err == nil {
			mutateFn = func() error {
				exist.Spec = expect.Spec
				return nil
			}
			obj = exist
		}
	}
	return retry.RetryOnConflict(retry.DefaultRetry, func() error {
		_, err := controllerutil.CreateOrPatch(ctx, clt, obj, mutateFn)
		return err
	})
}
